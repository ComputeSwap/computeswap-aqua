# ComputeSwap on Aqua

Log-curve concentrated liquidity, LP weight splits, and Dutch auctions as a **1inch Aqua app**. Uses the unmodified Aqua core in `lib/aqua`. **Powered by Aqua — © Degensoft Ltd 2025.**

Trading function (USDC per ETH, range \([p_a,p_b]\)):

$$(x + p_b^{-1})\,e^{\,y + 1 + \ln p_a} = e$$

Each LP position is one Aqua strategy (minipool): same `LogCurveMath` as the separate Uniswap hook project, but no shared v4 pool.

## Architecture

See [docs/AQUA.md](docs/AQUA.md) for ship/dock rollover, vault custody, and limitations. Weight mechanics: [docs/WEIGHTS.md](docs/WEIGHTS.md) (Aqua vault paths).

```
src/
  aqua/              ComputeAquaApp, AquaWeightVault, IAqua
  libraries/         LogCurveMath (+ v4 FullMath/TickMath via lib/v4-core)
  weights/           WeightToken (ERC-6909), WeightAuction
script/
  DeployAquaLocal.s.sol   local Aqua core + full stack
  DeployAquaApp.s.sol     app/vault/auction on existing Aqua
test/
  AquaIntegration.t.sol   real Aqua core, e2e
  MathBounds.t.sol        optional LogCurveMath bound samples (writes reports/*.csv)
```

## Build and test

```bash
forge build
forge test
```

Run pinned Aqua core tests from the submodule root:

```bash
cd lib/aqua && forge test
```

Aqua integration only:

```bash
forge test --match-contract AquaIntegrationTest -vv
```

Foundry may use Solidity **0.8.30** for Aqua core and **0.8.26** for ComputeSwap contracts.

## Local demo

Terminal 1:

```bash
anvil --port 8546
```

Terminal 2 (use an Anvil test account private key, not a mainnet key):

```bash
export PRIVATE_KEY='PASTE_ANVIL_TEST_PRIVATE_KEY_HERE'
forge script script/DeployAquaLocal.s.sol:DeployAquaLocal \
  --rpc-url http://127.0.0.1:8546 --broadcast
```

Terminal 3 (Next.js UI; reads `frontend/deployments.json` from the deploy script):

```bash
cd frontend && npm install && npm run dev
```

Open http://localhost:3000 — use **Mint test tokens** for WETH/USDC, then add liquidity, swap against a position, split weights, and run auctions.

**Vercel:** set project **Root Directory** to `frontend` (not the repo root), then redeploy.

**Aqua testnet (Ethereum Sepolia):** step-by-step in [docs/DEPLOY_SEPOLIA.md](docs/DEPLOY_SEPOLIA.md).

```bash
cp .env.example .env   # fill PRIVATE_KEY, TREASURY_ADDRESS, SEPOLIA_RPC_URL
set -a && source .env && set +a
forge script script/DeployAquaSepolia.s.sol:DeployAquaSepolia \
  --rpc-url "$SEPOLIA_RPC_URL" --broadcast --verify
```

## Dependencies

| library | role |
|---|---|
| `lib/aqua` | 1inch Aqua core (Aqua Source License) |
| `lib/v4-core` | **FullMath, TickMath only** (no PoolManager in this repo) |
| solady, solmate, forge-std | tokens, tests, scripts |

## License

Aqua-specific files: **LicenseRef-Degensoft-Aqua-Source-1.1** (see `lib/aqua/LICENSE`). `LogCurveMath` and shared weight code retain the repo **BUSL-1.1** in [LICENSE](LICENSE) unless you relicense separately.

Prototype — **not audited**.
