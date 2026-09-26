"use client";
import { connectWallet, faucet, scheduleRefresh, setAccount } from "@/lib/app";
import { fmtNum } from "@/lib/format";
import { activePosition } from "@/lib/pools";
import { useStore } from "@/lib/store";
import { fEth, fUsdc, NAMES, short } from "@/lib/ui";

export default function Header() {
  const { dep, local, me, signers, eth, usdc, positions, activePoolId } =
    useStore();
  const active = activePosition(positions, activePoolId);
  return (
    <header className="bar">
      <div className="brand">
        x·e<sup>y</sup>{" "}
        <span className="net muted">{local ? "local" : dep?.chainName || ""}</span>
        {positions.length ? (
          <span className="brand-meta num muted">
            {positions.length} pool{positions.length === 1 ? "" : "s"}
            {active ? ` · active $${fmtNum(active.price, 4)}` : ""}
          </span>
        ) : null}
      </div>
      <div className="bar-right">
        {local ? (
          <select
            aria-label="Wallet"
            onChange={(e) => {
              setAccount(Number(e.target.value));
              useStore.setState({ pop: null });
              void scheduleRefresh();
            }}
          >
            {signers.map((s, i) => (
              <option key={s.address} value={i}>
                {NAMES[i]}
              </option>
            ))}
          </select>
        ) : (
          <button
            type="button"
            className="small"
            onClick={() => void connectWallet()}
          >
            {me ? short(me) : "Connect wallet"}
          </button>
        )}
        <span className="num muted">
          {me ? `${fEth(eth, local ? 2 : 4)} ETH · ${fUsdc(usdc, 2)} USDC` : ""}
        </span>
        {(local && (dep?.usdcMintable || dep?.wethMintable)) ||
        (!local && dep?.usdcMintable) ? (
          <button
            type="button"
            className="ghost small"
            onClick={() => void faucet()}
          >
            {local ? "Mint test tokens" : "+10,000 test USDC"}
          </button>
        ) : null}
      </div>
    </header>
  );
}
