import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Http "http";
import Iter "mo:base/Iter";
import NftTypes "types";
import Text "mo:base/Text";

module Static {
    public type Asset = {
        contentType : Text;
        payload : [Blob];
    };

    public type AssetRequest = {
        // Remove asset with the given name.
        #Remove : {
            key : Text;
            callback : ?NftTypes.Callback;
        };
        // Inserts/Overwrites the asset.
        #Put : {
            key : Text;
            contentType : Text;
            payload : {
                #Payload : Blob;
                // Uses the staged data that was written by #StagedWrite.
                #StagedData;
            };
            callback : ?NftTypes.Callback;
        };
        // Stage (part of) an asset.
        #StagedWrite : NftTypes.StagedWrite;
    };

    public class Assets(assets: [(Text, Asset)]) {
        var stagedAssetData = Buffer.Buffer<Blob>(0);
        let staticAssets = HashMap.fromIter<Text, Asset>(
            assets.vals(),
            10,
            Text.equal,
            Text.hash,
        );

        public func entries() : Iter.Iter<(Text, Asset)> {
            return staticAssets.entries();
        };

        public func getToken(id : Text) : ?Asset {
            staticAssets.get(id);
        };

        // Returns a list of all static assets.
        public func list() : [(
            Text, // Name (key).
            Text, // Content type.
            Nat,  // Total size (number of bytes) of the payload.
        )] {
            let assets = Array.init<(Text, Text, Nat)>(
                staticAssets.size(), ("", "", 0),
            );

            var i = 0;
            for ((k, v) in staticAssets.entries()) {
                assets[i] := (
                    k,
                    v.contentType,
                    sum(v.payload.vals()),
                );
                i += 1;
            };
            return Array.freeze(assets);
        };

        // Returns a static asset based on the given key (path).
        // If the path is not found `index.html` gets returned (if defined).
        // Limitation: a shared function is only allowed as a public field of an actor.
        public func get(key : Text, callback : Http.StreamingCallback) : Http.Response {
            switch(staticAssets.get(key)) {
                case null {
                    // If the path was 'index.html' and it was not found, return 404.
                    if (key == "/index.html") return Http.NOT_FOUND();
                    // Otherwise return the index page.
                    return get("/index.html", callback);
                };
                case (?asset) {
                    if (asset.payload.size() == 1) {
                        return {
                            body = asset.payload[0];
                            headers = [("Content-Type", asset.contentType)];
                            status_code = 200;
                            streaming_strategy = null;
                        };
                    };
                    // Content is devided in chunks.
                    Http.handleLargeContent(
                        key,
                        asset.contentType,
                        asset.payload,
                        callback,
                    );
                };
            };
        };

        // Handles the given asset request, see AssetRequest for possible actions.
        public func handleRequest(data : AssetRequest) : async () {
            switch(data) {
                case(#Put(v)) {
                    switch(v.payload) {
                        case(#Payload(data)) {
                            staticAssets.put(
                                v.key,
                                {
                                    contentType = v.contentType;
                                    payload     = [data];
                                },
                            );
                        };
                        case (#StagedData) {
                            staticAssets.put(
                                v.key,
                                {
                                    contentType = v.contentType;
                                    payload = stagedAssetData.toArray()
                                },
                            );
                            // Reset staged data.
                            stagedAssetData := Buffer.Buffer(0);
                        };
                    };
                    ignore NftTypes.notify(v.callback);
                };

                case(#Remove(v)) {
                    staticAssets.delete(v.key);
                    ignore NftTypes.notify(v.callback);
                };

                case(#StagedWrite(v)) {
                    switch(v) {
                        case (#Init(v)) {
                            stagedAssetData := Buffer.Buffer(v.size);
                            ignore NftTypes.notify(v.callback);
                        };
                        case (#Chunk(v)) {
                            stagedAssetData.add(v.chunk);
                            ignore NftTypes.notify(v.callback);
                        };
                    };
                };
            };
        };

        // Returns the total length of the list of blobs.
        private func sum(bs : Iter.Iter<Blob>) : Nat {
            var sum = 0;
            Iter.iterate<Blob>(bs, func(x,_) {
                sum += x.size();
            });
            sum;
        };
    };
}
