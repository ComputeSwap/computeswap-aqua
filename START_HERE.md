# ComputeSwap Aqua export

This archive contains the complete current ComputeSwap source, the new Aqua app and vault, the Dutch auction, tests, deployment scripts, documentation, and the pinned Solidity dependencies needed to build them.

Snapshot: 2026-09-26. ComputeSwap base commit: `aa9f386a6bb835ffcc8e73289f98d0fff1118a61`, plus the local Aqua integration work. Official Aqua core: `ef24220ed9647555727b06867bf509cd6959d84b`. Additional Solidity packages: OpenZeppelin Contracts `5.4.0` and 1inch Solidity Utils `6.9.9`.

## Build and test

Extract the ZIP, open a terminal in the extracted `computeswap-aqua` folder, and run:

```bash
forge build
forge test
```

To run only the Aqua integration tests:

```bash
forge test --match-contract AquaIntegrationTest -vv
```

Foundry must be installed. It may download Solidity 0.8.26 and 0.8.30 on the first build. The Aqua source and required Solidity package sources are already included as regular files, so no Git submodule or Node package installation is required for these commands.

## Local Aqua demo

In one terminal:

```bash
anvil --port 8546
```

In a second terminal, in this folder, replace the placeholder with a private key displayed by that local Anvil instance:

```bash
export PRIVATE_KEY='PASTE_ANVIL_TEST_PRIVATE_KEY_HERE'
forge script script/DeployAquaLocal.s.sol:DeployAquaLocal \
  --rpc-url http://127.0.0.1:8546 --broadcast
```

This creates the local Aqua core, ComputeSwap app, vault, weight token, auction, mock WETH/USDC, and a funded LP position. See [docs/AQUA.md](docs/AQUA.md) for the architecture and deployment details.

The existing frontend is the Uniswap version and is not connected to Aqua. Its included deployment addresses refer to a prior local session; follow the root README to redeploy before running that interface.

Git history, build outputs, caches, broadcast records, and general JavaScript dependencies are omitted. Original contract source files are unchanged by packaging. The two Solidity packages under `lib/aqua/node_modules` are intentionally included to preserve the project's existing import paths.

Licenses and attribution are included with their respective components. Aqua — © Degensoft Ltd 2025.
