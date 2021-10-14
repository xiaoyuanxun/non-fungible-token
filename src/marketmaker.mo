import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Types "types";

module MarketMaker {
    public type TokenMarketMeta = {

    };

    public type SalesPrice = {
        #ICP : {
            e8s : Nat64
        };
    };

    public type TokenMarketState = {
        #BuyItNow : {
            price : SalesPrice; 
            meta  : TokenMarketState;
        };
    };

    public type TokenListStateError = {
        #AlreadyListed;
        #NotListed
    };

    public type TokenPurchaseError = {
        #TokenNotListed;
        #NotYetImplemented;
        #InvalidParameters   : Text;
        #IncorrectAmountSent : {sent : SalesPrice; ask : SalesPrice};
        #TransferFailure : Types.Error
    };

    public class MarketMaker(tokenStateEntries : [(Text, TokenMarketState)]) {
        let tokenStates = HashMap.HashMap<Text, TokenMarketState>(tokenStateEntries.size(), Text.equal, Text.hash);
        
        public func isListed(tokenId : Text) : Bool {
            switch(tokenStates.get(tokenId)) {
                case null false;
                case (?_) true;
            };
        };
        
        public func listToken(tokenId : Text, listingType : TokenMarketState) : Result.Result<(), TokenListStateError> {
            switch (tokenStates.get(tokenId)) {
                case (?_) {return #err(#AlreadyListed)};
                case null {
                    tokenStates.put(tokenId, listingType);
                    return #ok();
                };
            };
        };

        public func delistToken(tokenId : Text) : Result.Result<(), TokenListStateError> {
            tokenStates.delete(tokenId);
            #ok();
        };

        public func handleIncomingPayment(tokenId : Text, purchaser : Principal, amount : SalesPrice) : Result.Result<(), TokenPurchaseError> {
            switch(tokenStates.get(tokenId)) {
                case null {return #err(#TokenNotListed)};
                case (?tokenState) {
                    switch(tokenState) {
                        case (#BuyItNow(v)) {
                            if (v.price != amount) {
                                return #err(#IncorrectAmountSent({sent = amount; ask = v.price}));
                            };

                            return #ok();
                        };
                        case _ {
                            assert false; // Trap;
                            return #err(#NotYetImplemented);
                        };
                    };
                };
            }
        };

        private func handleBuyItNow() {

        };
    };
}