# Deploy ComputeSwap on Aqua (Ethereum Sepolia)

Aqua’s public test deployment is **Ethereum Sepolia** (chain id `11155111`). The Aqua registry uses the same address as on mainnet-family chains:

| Contract | Address |
|----------|---------|
| Aqua | `0x1111113ccf1426a8e30e2bff5e005d929bf6a90a` |
| SwapVM router (optional) | `0x111111338c5091e8440b67b168bae16a668ac0de` |

Sepolia tokens used by the deploy script:

| Token | Address |
|-------|---------|
| WETH | `0xfff9976782d46CC05630D1f6eBAb18b2324d6B14` |
| USDC (Circle) | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |

Confirm addresses in [1inch Aqua docs](https://business.1inch.com/portal/documentation/aqua/getting-started/build-an-aquaapp) and [Circle USDC addresses](https://developers.circle.com/stablecoins/usdc-contract-addresses) before mainnet-style deployments.

## 1. Fund the deployer

1. Sepolia ETH — any public faucet.
2. Sepolia USDC — [Circle faucet](https://faucet.circle.com) (needed if `SEED_POSITION=true`).

## 2. Configure environment

Copy `.env.example` to `.env` in the repo root and set:

- `PRIVATE_KEY` — deployer (never commit).
- `TREASURY_ADDRESS` — receives auction protocol fees (often the deployer).
- `SEPOLIA_RPC_URL` — Alchemy/Infura/public RPC.
- `ETHERSCAN_API_KEY` — for `--verify` (optional).

Optional:

- `SEED_POSITION=true` — mint one demo LP position after deploy (wraps ETH → WETH, spends USDC).
- `INIT_PRICE_USD=3000` — initial ETH price in USDC for the seeded range.

## 3. Broadcast

```bash
set -a && source .env && set +a

forge script script/DeployAquaSepolia.s.sol:DeployAquaSepolia \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY"
```

Dry run (no broadcast):

```bash
forge script script/DeployAquaSepolia.s.sol:DeployAquaSepolia \
  --rpc-url "$SEPOLIA_RPC_URL"
```

The script writes `frontend/deployments.json` with Sepolia addresses and `startBlock` for the indexer.

## 4. Frontend / Vercel

The Next.js app lives in `frontend/`. Git deploys **must** use **Root Directory → `frontend`** (Vercel → Project Settings → Build & Deployment). CLI: `vercel project update computeswap-aqua --root-directory frontend --auto-detect build-command --auto-detect install-command --auto-detect output-directory`. `frontend/vercel.json` holds the cron config.

1. Commit or upload the updated `frontend/deployments.json`.
2. In Vercel project settings, set:
   - `INDEXER_RPC_URL` — same Sepolia RPC (server-side).
   - `DATABASE_URL` — Neon/Postgres for history (recommended on Vercel).
3. Redeploy the frontend.

Local UI against Sepolia:

```bash
cd frontend && npm run dev
```

Connect MetaMask to Sepolia; use WETH + USDC (not native ETH for swaps/add liquidity).

## 5. GitHub Actions

Workflow: **Deploy Aqua Sepolia** (`.github/workflows/deploy-aqua-sepolia.yml`), manual dispatch only.

Create a GitHub **environment** named `testnet-sepolia` (Settings → Environments → Environment secrets) and add:

| Secret | Required | Purpose |
|--------|----------|---------|
| `TREASURY_ADDRESS` | Yes | Auction treasury (`WeightAuction` constructor) |
| `AQUA_SEPOLIA_DEPLOYER_PRIVATE_KEY` or `PRIVATE_KEY` | For broadcast | Deployer wallet (with `0x` prefix) |
| `SEPOLIA_RPC_URL` or `AQUA_SEPOLIA_RPC_URL` | Recommended | Sepolia RPC; simulate can use public fallback |
| `ETHERSCAN_API_KEY` | For verify | Contract verification when **verify** is enabled |
| `AQUA_SEPOLIA_RPC_PUBLIC_URL` | Optional | RPC in `frontend/deployments.json` (use a public URL if the indexer RPC is private) |
| `AQUA_ADDRESS` / `WETH_ADDRESS` / `USDC_ADDRESS` | Optional | Override defaults in `DeployAquaSepolia.s.sol` |

Alias `AQUA_TREASURY_ADDRESS` is still accepted if you prefer that name over `TREASURY_ADDRESS`.

Run with **broadcast** unchecked to simulate; check **broadcast** for a live deploy. Successful broadcasts upload `deployments.json` as artifact `deployments-aqua-sepolia`.

## 6. App-only deploy (no seed, no JSON extras)

If you only need contracts and will edit `deployments.json` by hand:

```bash
export AQUA_ADDRESS=0x1111113ccf1426a8e30e2bff5e005d929bf6a90a
export TREASURY_ADDRESS=0xYourTreasury
export PRIVATE_KEY=0x...
forge script script/DeployAquaApp.s.sol:DeployAquaApp \
  --rpc-url "$SEPOLIA_RPC_URL" --broadcast
```
