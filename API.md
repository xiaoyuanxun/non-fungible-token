# Public API of the Hub Actor

## Table of Contents

- [Http Request](#http-request)
  - [Streaming Strategy](#streaming-strategy)

## Http Request

### `/nft/{id}`

Returns the NFT with the given `{id}`.

### `{static}`

Returns the static asset at the given path.

```motoko
public query func http_request(request : Http.Request) : async Http.Response
```

```motoko
type HeaderField = (Text, Text);

type Request = {
    body    : Blob;
    headers : [HeaderField];
    method  : Text;
    url     : Text;
};

Response = {
    body               : Blob;
    headers            : [HeaderField];
    status_code        : Nat16;
    streaming_strategy : ?StreamingStrategy;
};
```

### Streaming Strategy

Sometimes an NFT needs to be devided into chunk because it is too large. In this case a streaming strategy gets passed in the HTTP reponse.

```motoko
public type StreamingStrategy = {
    #Callback: {
        token    : StreamingCallbackToken;
        callback : StreamingCallback;
    };
};
```

In this case a callback is provided with a token and a callback that can be used to retreive the binary data corresponding with that token.

```motoko
public type StreamingCallback = query (StreamingCallbackToken) -> async (StreamingCallbackResponse);

public type StreamingCallbackToken =  {
    content_encoding : Text;
    index            : Nat;
    key              : Text;
};

public type StreamingCallbackResponse = {
    body  : Blob;
    token : ?StreamingCallbackToken;
};
```

You can find an [example](./examples/streaming.mo) in the [examples directory](./examples/).
