# Instructions

Woo! Lets you going.


## Local

First spin up a dfx instance using 

```bash
dfx start
```

If you're running into strange issues, you can either delete the `.dfx` folder or add `--clean` to the end of the above command. Note, this is destructive.

Next, deploy your contract using the following command

```bash
dfx deploy --no-wallet
```

Once your contract is deployed you need to initialize the contract. In order to do that you'll need your dfx identity. Get that using:

```bash
dfx identity get-principal
```

Now you're ready to initialize the contract. The following is an example initialization command. Substitute your own name, symbol, and principalId(s) below. 
🥚
```bash
dfx canister call nft init '(vec {principal "aaaaa-aa"}, record {name = "Cool Contract"; symbol = "🥚"})'
```

## Prod

First, grab your principalId just like you did when deploying locally

```bash
dfx identity get-principal
```

Next, grab you wallet principal using 

```bash
dfx identity --network ic get-wallet
```

Deploy the canister

```bash
dfx deploy --network ic nft --with-cycles 700000000000
```

Now, initialize the canister. Note, we have to make sure we're using our wallet canister to make this call. Replace the placeholder principals.

```bash
dfx canister --network ic --wallet my-wallet-canister call nft init '(vec {principal "my-principal"}, record {name = "Cool Contract"; symbol = "🥚"})'
```

## Notes

> If you're hacking locally make sure you remove `canister_ids.json` from the `.gitignore` file.
