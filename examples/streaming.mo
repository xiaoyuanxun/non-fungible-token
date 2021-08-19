// We use static.get to simplify the example.
// This behaves exactly the same as http_request.

import Blob "mo:base/Blob";
import S "../src/static";

// Start out with no assets.S
var A = S.Assets([]);
assert(A.list() == []);

// Initialize staging.
await A.handleRequest(
    #StagedWrite(
        #Init{
            size     = 3;
            callback = null; // Callback to get notified.
        },
    ),
);

// Staging the parts of the asset.
await A.handleRequest(
    #StagedWrite(
        #Chunk{
            chunk    = Blob.fromArray([0x00]);
            callback = null;
        },
    ),
);
await A.handleRequest(#StagedWrite(#Chunk{chunk=Blob.fromArray([0x01]);callback=null}));
await A.handleRequest(#StagedWrite(#Chunk{chunk=Blob.fromArray([0x02]);callback=null}));

// Create staged asset.
await A.handleRequest(
    #Put{
        key         = "a"; // Name of the asset to create.
        contentType = "";
        payload     = #StagedData;
        callback    = null;
    },
);

// Get first part of the asset (index = 0).
let p0 = A.get("a");
assert(p0.body == Blob.fromArray([0x00])); // Confirm data of part 1.
switch (p0.streaming_strategy) {
    case (null) { assert(false) }; // There should be a part 2.
    case (?#Callback(cb)) {
        assert(cb.token.index == 1);
        let p1 = await cb.callback(cb.token);
        assert(p1.body == Blob.fromArray([0x01])); // Confirm data of part 2.
        switch (p1.token) {
            case (null) { assert(false) }; // There should be a part 3.
            case (? p1t) {
                assert(p1t.index == 2);
                let p2 = await cb.callback(p1t);
                assert(p2.body == Blob.fromArray([0x02])); // Confirm data of part 3;
                assert(p2.token == null); // Last part.
            };
        };
    };
};
