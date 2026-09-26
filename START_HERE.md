# ComputeSwap Aqua

Aqua app, maker vault, weight token, auction, tests, and deploy scripts for the log-curve minipool design.

## Quick start

```bash
forge build
forge test
```

```bash
forge test --match-contract AquaIntegrationTest -vv
```

## Local demo

```bash
anvil --port 8546
```

```bash
export PRIVATE_KEY='PASTE_ANVIL_TEST_PRIVATE_KEY_HERE'
forge script script/DeployAquaLocal.s.sol:DeployAquaLocal \
  --rpc-url http://127.0.0.1:8546 --broadcast
```

Details: [docs/AQUA.md](docs/AQUA.md), [README.md](README.md).
