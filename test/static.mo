import Blob "mo:base/Blob";

import S "../src/static";

var staticAssets = S.Assets([]);
assert(staticAssets.list() == []);

let contentType = "application/octet-stream";
let a : S.Asset = {
    contentType = contentType;
    payload     = [Blob.fromArray([0x00, 0x00, 0x00])];
};

// Initialize assets.
staticAssets := S.Assets([("a", a)]);
assert(staticAssets.list() == [("a", contentType, 3)]);

// Get asset.
assert(staticAssets.get("a") == {
    body               = Blob.fromArray([0x00, 0x00, 0x00]);
    headers            = [("Content-Type", contentType)];
    status_code        = 200;
    streaming_strategy = null;
});

// Replace asset.
await staticAssets.handleRequest(#Put({
    key         = "a";
    contentType = contentType;
    payload     = #Payload(Blob.fromArray([0x00]));
    callback    = null;
}));
assert(staticAssets.list() == [("a", contentType, 1)]);

// Remove asset.
await staticAssets.handleRequest(#Remove({
    key = "a"; 
    callback = null;
}));
assert(staticAssets.list() == []);

// Create asset with PUT.
await staticAssets.handleRequest(#Put({
    key         = "a";
    contentType = contentType;
    payload     = #Payload(Blob.fromArray([0x01]));
    callback    = null;
}));
assert(staticAssets.get("a") == {
    body               = Blob.fromArray([0x01]);
    headers            = [("Content-Type", contentType)];
    status_code        = 200;
    streaming_strategy = null;
});

// Stage asset.
await staticAssets.handleRequest(#StagedWrite(#Init{
    size     = 2;
    callback = null;
}));
await staticAssets.handleRequest(#StagedWrite(#Chunk{
    chunk     = Blob.fromArray([0x00]);
    callback = null;
}));
await staticAssets.handleRequest(#StagedWrite(#Chunk{
    chunk     = Blob.fromArray([0x01]);
    callback = null;
}));

// Create staged asset.
await staticAssets.handleRequest(#Put({
    key         = "a";
    contentType = contentType;
    payload     = #StagedData;
    callback    = null;
}));

// Get staged asset.
let nA = staticAssets.get("a");
assert(nA.body == Blob.fromArray([0x00]));
switch (nA.streaming_strategy) {
    case null  { assert (false) };
    case (? #Callback(v)) {
        let token = v.token;
        assert(token.content_encoding == "gzip");
        assert(token.index == 1);
        assert(token.key == "a");
        let next = await v.callback(token);
        assert(next.body == Blob.fromArray([0x01]));
        assert(next.token == null);
    };
};
