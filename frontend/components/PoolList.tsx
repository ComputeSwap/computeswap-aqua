"use client";
import { nameOf, openPositionPop, selectPool } from "@/lib/app";
import { fmtNum } from "@/lib/format";
import { isMe, useStore } from "@/lib/store";
import { fEth, fUsdc, toEth, toUsdc } from "@/lib/ui";

export default function PoolList() {
  const { positions, activePoolId, dep } = useStore();
  return (
    <aside className="pool-rail">
      <div className="pool-rail-head">
        <h2>Pools</h2>
        <span className="muted num">
          {positions.length} {positions.length === 1 ? "strategy" : "strategies"}
        </span>
      </div>
      <p className="pool-rail-note muted">
        Each pool is one Aqua LP position with its own price and range. Select a
        pool to trade against it.
      </p>
      {positions.length === 0 ? (
        <p className="pool-empty muted">
          No pools on-chain yet. Create the first one with the form on the
          right{dep?.initPrice ? ` (reference price $${fmtNum(dep.initPrice, 0)})` : ""}.
        </p>
      ) : (
        <ul className="pool-list">
          {positions.map((p) => {
            const on = activePoolId === p.id;
            const value = toEth(p.eth) * p.price + toUsdc(p.usdc);
            return (
              <li key={p.id} className={`pool-list-item${on ? " on" : ""}`}>
                <div
                  role="button"
                  tabIndex={0}
                  className={`pool-card${on ? " on" : ""}`}
                  onClick={() => selectPool(p.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      selectPool(p.id);
                    }
                  }}
                >
                  <div className="pool-card-top">
                    <span className="pool-card-id">Pool #{p.id}</span>
                    <span className="num pool-card-price">
                      ${fmtNum(p.price, 4)}
                    </span>
                  </div>
                  <div className="pool-card-range num muted">
                    ${fmtNum(p.pa, 2)} – ${fmtNum(p.pb, 2)}
                  </div>
                  <div className="pool-card-meta num">
                    {fEth(p.eth, 3)} WETH · {fUsdc(p.usdc, 0)} USDC
                  </div>
                  <div className="pool-card-sub muted">
                    {isMe(p.owner) ? "You" : nameOf(p.owner)} · $
                    {fmtNum(value, 0)}
                  </div>
                </div>
                <button
                  type="button"
                  className="pool-card-manage small ghost"
                  data-pop-trigger
                  onClick={(e) => {
                    e.stopPropagation();
                    selectPool(p.id);
                    openPositionPop(p.id, e.currentTarget);
                  }}
                >
                  Manage
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </aside>
  );
}
