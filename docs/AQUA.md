# ComputeSwap on Aqua

This is a working, contract-level Aqua adaptation of ComputeSwap's log-curve AMM, LP weight vault, and Dutch auction. It uses the **unmodified 1inch Aqua core** as a pinned Git submodule (`lib/aqua`, commit `ef24220ed9647555727b06867bf509cd6959d84b`). Aqua — © Degensoft Ltd 2025.

## Architecture and the no-splitting workaround

The Uniswap hook manages a pooled price across many ranges, while Aqua records virtual token balances per `(maker, app, strategyHash, token)`. Aqua `ship`/`dock` operate on a whole immutable strategy; they do not split one strategy into separately redeemable token legs. The Aqua version therefore deliberately uses **one strategy per LP position**:

1. `AquaWeightVault` accepts WETH and USDC and holds them as the Aqua **maker**. Each LP receives an ERC-721 position. This is vault custody, unlike an ordinary Aqua strategy shipped directly from an LP's wallet.
2. The vault `ship`s exactly the deposited token amounts into a `ComputeAquaApp` strategy. The app implements the same `LogCurveMath` formulas as the Uniswap version. An input swap calls Aqua `push` and its output calls Aqua `pull`.
3. `split` **does not split Aqua's strategy or its tokens**. It locks position liquidity in the vault and mints an ERC-6909 claim on one leg. The existing `WeightAuction` escrows and sells that claim with an LP-chosen floor price.
4. On a partial exercise or withdrawal, the vault atomically `dock`s the entire old strategy, distributes only the removed slice, and `ship`s the remaining assets under a fresh strategy hash. The app carries the moving-average oracle into the replacement strategy. The old hash cannot be reused.
5. The weight holder receives the selected leg's **principal**; the current NFT owner receives the other principal leg and both legs' accrued swap fees. Expired claims unlock the LP liquidity without a transaction.

For a strategy with liquidity `L`, price `P`, and range `[p_a,p_b]`, the app uses the same reserves as the hook: `x(P)=L(1/P−1/p_b)` and `y(P)=L ln(P/p_a)`. Swap input is reduced by `feeBps` before applying the curve; the full input is pushed through Aqua, so fees remain in the maker wallet. The vault calculates fees as Aqua's virtual balance above the geometric principal and pays them pro rata on removal.

This design **does not** recreate a shared pool price, cross-range routing, native ETH support, or Aqua's usual LP-wallet self-custody. Each Aqua position is independently priced and uses ERC-20 WETH/USDC. A router or UI must select a particular position strategy. This is the intentional tradeoff for preserving exercisable weight rights and fully backed positions.

## Install and test

This standalone ZIP includes the pinned Aqua source and its Solidity dependencies. From the extracted project folder, with Foundry installed:

```bash
forge test --match-contract AquaIntegrationTest -vv
forge test
```

No Git submodule or pnpm installation is needed for this ZIP. The first build may download Solidity 0.8.30. Foundry auto-selects 0.8.30 for the official Aqua core and 0.8.26 for Uniswap's pinned `PoolManager`. The Aqua tests deploy and call the **actual official Aqua contract**, not a mock. They cover shipping, both swap directions, backing across randomized swaps and partial withdrawals, strategy rollover, auction purchase and fee, oracle-gated exercise, final exercise, expiry, and maker isolation.

## Run a local demo

In terminal 1:

```bash
anvil --port 8546
```

In terminal 2, set `PRIVATE_KEY` to **one of the fresh Anvil accounts shown in terminal 1** (never use a live-wallet key in a local demo), then run:

```bash
export PRIVATE_KEY='PASTE_ANVIL_TEST_PRIVATE_KEY_HERE'
forge script script/DeployAquaLocal.s.sol:DeployAquaLocal \
  --rpc-url http://127.0.0.1:8546 --broadcast
```

The script deploys Aqua core, the ComputeSwap Aqua app, vault, weight token, auction, mock WETH/USDC, and a funded example LP position. It prints all addresses. There is no bundled UI; integrators call the contracts directly or build a router/frontend against `ComputeAquaApp` and `AquaWeightVault`.

For a chain with an existing Aqua core, `script/DeployAquaApp.s.sol` deploys only the ComputeSwap app, vault, and auction. It reads `AQUA_ADDRESS`, `TREASURY_ADDRESS`, and `PRIVATE_KEY` from the environment; verify the Aqua address for that chain in [1inch's official deployment documentation](https://business.1inch.com/portal/documentation/aqua/getting-started/build-an-aquaapp) before broadcasting. This script has **not** been broadcast to a public network.

## Production considerations

- The new Aqua contracts are a prototype, **not audited**. Before real funds: independent smart-contract review, adversarial oracle/auction tests, token-behavior restrictions, and a transaction router/UI are needed.
- The dedicated maker vault gives up Aqua's usual LP self-custody and does **not** overcommit one token balance to multiple strategies. This is necessary for leg claim solvency.
- A swap that would cross a position's range reverts instead of partially filling or routing to another strategy.
- The current Aqua app supports exact-input swaps only; exact-output quoting/routing would be a separate addition.
- Strategy rollovers cost gas and change the hash; integrators must read `strategyOf(positionId)` again after every exercise or withdrawal.
- Only ordinary exact-transfer ERC-20s are supported. The vault and app reject fee-on-transfer behavior on deposits and swaps; rebasing or otherwise nonstandard tokens should not be listed without separate review.
- The reference Aqua repository has its own source license and commercial-use terms. Review [`lib/aqua/LICENSE`](../lib/aqua/LICENSE) and [`lib/aqua/LICENSES/Aqua-Source-1.1.txt`](../lib/aqua/LICENSES/Aqua-Source-1.1.txt) before distribution or deployment.
