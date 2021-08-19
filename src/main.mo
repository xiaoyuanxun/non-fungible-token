import Array "mo:base/Array";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Http "http";
import Iter "mo:base/Iter";
import MapHelper "mapHelper";
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Static "static";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Token "token";
import Types "types";

shared({ caller = hub }) actor class Hub() = this {
    var MAX_RESULT_SIZE_BYTES     = 1_000_000; // 1MB Default
    var HTTP_STREAMING_SIZE_BYTES = 1_900_000;

    stable var CONTRACT_METADATA : Types.ContractMetadata = {
        name   = "none"; 
        symbol = "none";
    };
    stable var INITALIZED : Bool = false;

    stable var TOPUP_AMOUNT             = 2_000_000;
    stable var BROKER_CALL_LIMIT        = 25;
    stable var BROKER_FAILED_CALL_LIMIT = 25;

    stable var id          = 0;
    stable var payloadSize = 0;
    stable var nftEntries : [(
        Text, // Token Identifier.
        (
            ?Principal, // Owner of the token.
            [Principal] // Authorized principals.
        ),
        Types.Nft // NFT data.
    )] = [];
    let nfts = Token.NTFs(
        id, 
        payloadSize, 
        nftEntries,
    );

    stable var staticAssetsEntries : [(
        Text,        // Asset Identifier (path).
        Static.Asset // Asset data.
    )] = [];
    let staticAssets = Static.Assets(staticAssetsEntries);
    
    stable var contractOwners : [Principal] = [hub];
    
    stable var messageBrokerCallback : ?Types.EventCallback = null;
    stable var messageBrokerCallsSinceLastTopup : Nat = 0;
    stable var messageBrokerFailedCalls : Nat = 0;

    public shared ({caller}) func setEventCallback(cb : Types.EventCallback) : async () {
        assert(_isOwner(caller));
        messageBrokerCallback := ?cb;
    };

    public shared ({caller}) func getEventCallbackStatus() : async Types.EventCallbackStatus {
        assert(_isOwner(caller));
        return {
            callback            = messageBrokerCallback;
            callsSinceLastTopup = messageBrokerCallsSinceLastTopup;
            failedCalls         = messageBrokerFailedCalls;
            noTopupCallLimit    = BROKER_CALL_LIMIT;
            failedCallsLimit    = BROKER_FAILED_CALL_LIMIT;
        };
    };

    system func preupgrade() {
        id                  := nfts.currentID();
        payloadSize         := nfts.payloadSize();
        nftEntries          := Iter.toArray(nfts.entries());
        staticAssetsEntries := Iter.toArray(staticAssets.entries());
    };

    system func postupgrade() {
        id                  := 0;
        payloadSize         := 0;
        nftEntries          := [];
        staticAssetsEntries := [];
    };

    // Initializes the contract with the given (additional) owners and metadata. Can only be called once.
    // @pre: isOwner
    public shared({caller}) func init(
        owners   : [Principal],
        metadata : Types.ContractMetadata,
    ) : async () {
        assert(not INITALIZED and caller == hub);
        contractOwners    := Array.append(contractOwners, owners);
        CONTRACT_METADATA := metadata;
        INITALIZED        := true;
    };

    // Returns the meta data of the contract.
    public query func getMetadata() : async Types.ContractMetadata {
        CONTRACT_METADATA;
    };

    // Returns the total amount of minted NFTs.
    public query func getTotalMinted() : async Nat {
        nfts.getTotalMinted();
    };

    public shared({caller}) func wallet_receive() : async () {
        ignore ExperimentalCycles.accept(ExperimentalCycles.available());
    };

    // Mints a new egg.
    // @pre: isOwner
    public shared ({caller}) func mint(egg : Token.Egg) : async Text {
        assert(_isOwner(caller));
        let (id, owner) = await nfts.mint(Principal.fromActor(this), egg);
        ignore _emitEvent({
            createdAt     = Time.now();
            event         = #ContractEvent(
                #Mint({
                    id    = id; 
                    owner = owner;
                }),
            );
            topupAmount   = TOPUP_AMOUNT;
            topupCallback = wallet_receive;
        });
        id;
    };

    // Writes a part of an NFT to the staged data. 
    // Initializing another NFT will destruct the data in the buffer.
    public shared({caller}) func writeStaged(data : Types.StagedWrite) : async () {
        assert(_isOwner(caller));
        await nfts.writeStaged(data);
    };

    // Returns the contract info.
    // @pre: isOwner
    public shared ({caller}) func getContractInfo() : async Types.ContractInfo {
        assert(_isOwner(caller));
        return {
            heap_size        = Prim.rts_heap_size();
            memory_size      = Prim.rts_memory_size();
            max_live_size    = Prim.rts_max_live_size();
            nft_payload_size = payloadSize; 
            total_minted     = nfts.getTotalMinted(); 
            cycles           = ExperimentalCycles.balance();
            authorized_users = contractOwners;
        };
    };

    // List all static assets.
    // @pre: isOwner
    public query ({caller}) func listAssets() : async [(Text, Text, Nat)] {
        assert(_isOwner(caller));
        staticAssets.list();
    };

    // Allows you to replace delete and stage NFTs.
    // Putting and initializing staged data will overwrite the present data.
    public shared ({caller}) func assetRequest(data : Static.AssetRequest) : async (){
        assert(_isOwner(caller));
        await staticAssets.handleRequest(data);
    };

    // Returns the tokens of the given principal.
    public func tokensOf(p : Principal) : async [Text] {
        nfts.tokensOf(p);
    };

    // Returns the owner of the NFT with given identifier.
    public shared func ownerOf(id : Text) : async Result.Result<Principal, Types.Error> {
        nfts.ownerOf(id);
    };

    // Transfers one of your own NFTs to another principal.
    public shared ({caller}) func transfer(to : Principal, id : Text) : async Result.Result<(), Types.Error> {
        let owner = switch (_canChange(caller, id)) {
            case (#err(e)) { return #err(e); };
            case (#ok(v))  { v; };
        };
        let res = await nfts.transfer(to, id);
        ignore _emitEvent({
            createdAt     = Time.now();
            event         = #NftEvent(
                #Transfer({
                    from = owner; 
                    to   = to; 
                    id   = id;
                }));
            topupAmount   = TOPUP_AMOUNT;
            topupCallback = wallet_receive;
        });
        res;
    };

    // Allows the caller to authorize another principal to act on its behalf.
    public shared ({caller}) func authorize(req : Token.AuthorizeRequest) : async Result.Result<(), Types.Error> {
        switch (_canChange(caller, req.id)) {
            case (#err(e)) { return #err(e); };
            case (#ok(v))  { };
        };
        if (not nfts.authorize(req)) {
            return #err(#AuthorizedPrincipalLimitReached(Token.AUTHORIZED_LIMIT))
        };
        ignore _emitEvent({
            createdAt     = Time.now();
            event         = #NftEvent(
                #Authorize({
                    id           = req.id; 
                    user         = req.p; 
                    isAuthorized = req.isAuthorized;
                }));
            topupAmount   = TOPUP_AMOUNT;
            topupCallback = wallet_receive;
        });
        #ok();
    };

    private func _canChange(caller : Principal, id : Text) : Result.Result<Principal,Types.Error> {
        let owner = switch (nfts.ownerOf(id)) {
            case (#err(e)) {
                if (not _isOwner(caller)) return #err(e);
                Principal.fromActor(this);
            };
            case (#ok(v))  {
                // The owner not is the caller.
                if (not _isOwner(caller) and v != caller) {
                    // Check whether the caller is authorized.
                    if (not nfts.isAuthorized(caller, id)) return #err(#Unauthorized);
                };
                v;
            };
        };
        #ok(owner);
    };

    // Returns whether the given principal is authorized to change to NFT with the given identifier.
    public shared func isAuthorized(id : Text, p : Principal) : async Bool {
        nfts.isAuthorized(p, id);
    };

    // Returns which principals are authorized to change the NFT with the given identifier.
    public shared func getAuthorized(id : Text) : async [Principal] {
        nfts.getAuthorized(id);
    };

    public shared({caller}) func tokenByIndex(id : Text) : async Result.Result<Types.PublicNft, Types.Error> {
        switch(nfts.getToken(id)) {
            case (#err(e)) { return #err(e); };
            case (#ok(v)) {
                if (v.isPrivate) {
                    if (not nfts.isAuthorized(caller, id) and not _isOwner(caller)) {
                        return #err(#Unauthorized);
                    };
                };
                var payloadResult : Types.PayloadResult = #Complete(v.payload[0]);
                if (v.payload.size() > 1) {
                    payloadResult := #Chunk({
                        data       = v.payload[0]; 
                        totalPages = v.payload.size(); 
                        nextPage   = ?1;
                    });
                };
                let owner = switch (nfts.ownerOf(id)) {
                    case (#err(_)) { Principal.fromActor(this); };
                    case (#ok(v))  { v;                         }; 
                };
                return #ok({
                    contentType = v.contentType;
                    createdAt = v.createdAt;
                    id = id;
                    owner = owner;
                    payload = payloadResult;
                    properties = v.properties;
                });
            }
        }
    };
    
    public shared ({caller}) func tokenChunkByIndex(id : Text, page : Nat) : async Types.ChunkResult {
        switch (nfts.getToken(id)) {
            case (#err(e)) { return #err(e); };
            case (#ok(v)) {
                if (v.isPrivate) {
                    if (not nfts.isAuthorized(caller, id) and not _isOwner(caller)) {
                        return #err(#Unauthorized);
                    };
                };
                let totalPages = v.payload.size();
                if (page > totalPages) {
                    return #err(#InvalidRequest);
                };
                var nextPage : ?Nat = null;
                if (totalPages > page + 1) {
                    nextPage := ?(page + 1);
                };
                #ok({
                    data       = v.payload[page];
                    nextPage   = nextPage;
                    totalPages = totalPages;
                });
            };
        };
    };

    private func _isOwner(p : Principal) : Bool {
        switch(Array.find<Principal>(contractOwners, func(v) {return v == p})) {
            case (null) { false; };
            case (? v)  { true;  };
        };
    };

    private func _emitEvent(event : Types.EventMessage) : async () {
        let emit = func(broker : Types.EventCallback, msg : Types.EventMessage) : async () {
            try {
                await broker(msg);
                messageBrokerCallsSinceLastTopup := messageBrokerCallsSinceLastTopup + 1;
                messageBrokerFailedCalls := 0;
            } catch(_) {
                messageBrokerFailedCalls := messageBrokerFailedCalls + 1;
                if (messageBrokerFailedCalls > BROKER_FAILED_CALL_LIMIT) {
                    messageBrokerCallback := null;
                };
            };
        };

        switch(messageBrokerCallback) {
            case (null)    { return; };
            case (?broker) {
                if (messageBrokerCallsSinceLastTopup > BROKER_CALL_LIMIT) return;
                ignore emit(broker, event);
            };
        };
    };

    // HTTP interface

    public query func http_request(request : Http.Request) : async Http.Response {
        let path = Iter.toArray(Text.tokens(request.url, #text("/")));
        if (path.size() != 0 and path[0] == "nft") {
            if (path.size() != 2) {
                return Http.BAD_REQUEST();
            };
            return nfts.get(path[1]);
        };
        return staticAssets.get(request.url, staticStreamingCallback);
    };

    // A streaming callback based on static assets.
    // Returns {[], null} if the asset can not be found.
    public query func staticStreamingCallback(tk : Http.StreamingCallbackToken) : async Http.StreamingCallbackResponse {
        switch(staticAssets.getToken(tk.key)) {
            case null return {
                body = Blob.fromArray([]);
                token = null;
            };
            case (? v) {
                let (body, token) = Http.streamContent(
                    tk.key,
                    tk.index,
                    v.payload,
                );
                return {
                    body = body;
                    token = token;
                };
            };
        };
    };
}