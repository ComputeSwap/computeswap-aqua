"use client";
import {
  auctionAnnounced,
  auctionPrice,
  fmtDuration,
  openSplit,
  weightAction,
} from "@/lib/app";
import * as C from "@/lib/curve.js";
import { fmtNum } from "@/lib/format";
import { type Auction, isMe, now, useStore } from "@/lib/store";
import { fEth, filterDecimal, toEth, toUsdc } from "@/lib/ui";
import PayoffCanvas from "./PayoffCanvas";

export default function Weights() {
  const {
    auctions,
    series,
    positions,
    pool,
    openPayoff,
    buyPct,
    me,
    chainBlock,
    activePoolId,
  } = useStore();
  useStore((s) => s.tick);
  void me;
  void chainBlock;
  const t = now();
  const price = pool.initialized ? pool.price : 0;
  const seriesOf = (id: number) => series.find((s) => s.id === id);
  const live = auctions.filter(
    (a) => a.remaining > 0n && (seriesOf(a.seriesId)?.expiry ?? 0) > t,
  );
  const held = series.filter((s) => s.balance > 0n && s.expiry > t);
  const myPools = positions.filter((p) => isMe(p.owner));
  const togglePayoff = (key: string) => {
    const next = new Set(openPayoff);
    next.has(key) ? next.delete(key) : next.add(key);
    useStore.setState({ openPayoff: next });
  };
  const Toggle = ({ k }: { k: string }) => (
    <button
      type="button"
      className={`small ghost${openPayoff.has(k) ? " on" : ""}`}
      onClick={() => togglePayoff(k)}
    >
      Payoff diagram
    </button>
  );
  const lotPrice = (a: Auction) =>
    (auctionPrice(a, t) * Number(a.remaining)) / Number(a.lot);

  if (!live.length && !held.length) {
    if (!myPools.length) {
      return (
        <p className="weights-empty muted">
          {me
            ? "No pools you own yet. Weights appear after you create a pool and split off ETH to sell or hold."
            : "Connect a wallet to split ETH weights from your pools."}
        </p>
      );
    }
    const focus =
      myPools.find((p) => p.id === activePoolId) ?? myPools[0];
    return (
      <div className="weights-empty">
        <p className="muted">
          No active weights or auctions. Split ETH from your liquidity to mint a
          weight (sell it at auction or exercise later).
        </p>
        <ul className="weights-pool-actions">
          {myPools.map((p) => (
            <li key={p.id}>
              <span className="num">
                Pool #{p.id} · ${fmtNum(p.pa, 2)}–${fmtNum(p.pb, 2)}
              </span>
              <button
                type="button"
                className="small"
                onClick={() => openSplit(p.id)}
              >
                Sell ETH weight
              </button>
            </li>
          ))}
        </ul>
        {myPools.length > 1 ? (
          <p className="sub muted">
            Focus pool #{focus.id} is selected in the sidebar.
          </p>
        ) : null}
      </div>
    );
  }

  return (
    <div>
      {live.map((a) => {
        const s = seriesOf(a.seriesId);
        const pos = positions.find((p) => p.id === s?.positionId);
        const ethNow = pos
          ? C.reserves({ ...pos, L: Number(a.remaining) / 1e6 }, price).x
          : 0;
        const announced = auctionAnnounced(a);
        const floor =
          (toUsdc(a.floorPrice) * Number(a.remaining)) / Number(a.lot);
        const key = `a${a.id}`;
        return (
          <div className="witem" key={key}>
            <div className="item">
              <div>
                For sale: position #{s?.positionId}
                {pos ? (
                  <span className="sub">
                    {" "}
                    ${fmtNum(pos.pa, 4)}–${fmtNum(pos.pb, 4)}
                  </span>
                ) : null}
                <br />
                <span className="num">
                  {fmtNum(ethNow, 4)} ETH now ·{" "}
                  <b>
                    {announced
                      ? `listed at $${fmtNum(lotPrice(a), 2)}`
                      : `$${fmtNum(lotPrice(a), 2)}`}
                  </b>
                </span>{" "}
                <span className="sub">
                  {announced
                    ? "· announced · drops next block"
                    : t < a.end
                      ? `· falling for ${fmtDuration(a.end - t)} · floor $${fmtNum(floor, 2)}`
                      : `· at floor $${fmtNum(floor, 2)}`}
                  {s && s.expiry > t
                    ? ` · weight expires in ${fmtDuration(s.expiry - t)}`
                    : null}
                </span>
              </div>
              <div className="act">
                <Toggle k={key} />
                {isMe(a.seller) ? (
                  <button
                    type="button"
                    className="small ghost"
                    onClick={() => void weightAction("cancel", a.id)}
                  >
                    Cancel
                  </button>
                ) : announced ? null : (
                  <>
                    <input
                      type="text"
                      inputMode="decimal"
                      autoComplete="off"
                      value={buyPct[a.id] ?? "100"}
                      aria-label="Share to buy (%)"
                      onChange={(e) =>
                        useStore.setState({
                          buyPct: {
                            ...buyPct,
                            [a.id]: filterDecimal(e.target.value, 4),
                          },
                        })
                      }
                    />{" "}
                    %
                    <button
                      type="button"
                      className="small"
                      onClick={() => void weightAction("buy", a.id)}
                    >
                      Buy
                    </button>
                  </>
                )}
              </div>
            </div>
            {pos && openPayoff.has(key) ? (
              <PayoffCanvas
                pa={pos.pa}
                pb={pos.pb}
                L={Number(a.remaining) / 1e6}
                price={price}
                lines={[{ value: lotPrice(a), label: "auction price" }]}
              />
            ) : null}
          </div>
        );
      })}
      {held.map((s) => {
        const pv = s.preview;
        const pos = positions.find((p) => p.id === s.positionId);
        const owner = !!pos && isMe(pos.owner);
        const key = `s${s.id}`;
        if (!pv) {
          return null;
        }
        const devPct = (1.0001 ** (pv.tick - pv.ema) - 1) * 100;
        return (
          <div className="witem" key={key}>
            <div className="item">
              <div>
                {owner ? "Unsold weight" : "Your weight"}: position #
                {s.positionId}
                {pos ? (
                  <span className="sub">
                    {" "}
                    ${fmtNum(pos.pa, 4)}–${fmtNum(pos.pb, 4)}
                  </span>
                ) : null}
                <br />
                <span className="num">
                  {owner ? "" : "you get "}
                  <b>{fEth(pv.leg)} ETH</b> ($
                  {fmtNum(toEth(pv.leg) * price, 2)})
                </span>{" "}
                <span className="sub">
                  · expires in {fmtDuration(s.expiry - t)}
                </span>
                {pv.allowed || owner ? null : (
                  <>
                    <br />
                    <span className="sub">
                      Price is {fmtNum(Math.abs(devPct), 1)}% off its 10-min
                      average: exercise opens when it settles.
                    </span>
                  </>
                )}
              </div>
              <div className="act">
                <Toggle k={key} />
                {owner ? (
                  <button
                    type="button"
                    className="small ghost"
                    onClick={() => void weightAction("merge", s.id)}
                  >
                    Merge back
                  </button>
                ) : (
                  <button
                    type="button"
                    className="small"
                    disabled={!pv.allowed}
                    onClick={() => void weightAction("exercise", s.id)}
                  >
                    Exercise
                  </button>
                )}
              </div>
            </div>
            {pos && openPayoff.has(key) ? (
              <PayoffCanvas
                pa={pos.pa}
                pb={pos.pb}
                L={Number(s.balance) / 1e6}
                price={price}
                lines={[]}
              />
            ) : null}
          </div>
        );
      })}
    </div>
  );
}
