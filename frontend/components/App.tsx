"use client";
import { useEffect } from "react";
import { init, stop } from "@/lib/app";
import type { Deployment } from "@/lib/config";
import { useStore } from "@/lib/store";
import AddLiquidity from "./AddLiquidity";
import DebugToggle from "./DebugToggle";
import Header from "./Header";
import History from "./History";
import LiquidityChart from "./LiquidityChart";
import PoolList from "./PoolList";
import PositionPop from "./PositionPop";
import ReservesChart from "./ReservesChart";
import SplitModal from "./SplitModal";
import Swap from "./Swap";
import Toast from "./Toast";
import Weights from "./Weights";

export default function App({ dep }: { dep: Deployment | null }) {
  const busy = useStore((s) => s.busy);
  useEffect(() => {
    if (!dep) {
      return;
    }
    void init(dep);
    return stop;
  }, [dep]);
  useEffect(() => {
    document.body.classList.toggle("busy", busy);
  }, [busy]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        useStore.setState({ pop: null, splitFor: null });
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, []);
  if (!dep) {
    return (
      <p className="muted" style={{ padding: 24 }}>
        deployments.json not found: start anvil on port 8546 and run
        script/DeployAquaLocal.s.sol (see README)
      </p>
    );
  }
  return (
    <>
      <Header />
      <div className="shell">
        <div className="shell-rail">
          <PoolList />
          <LiquidityChart />
        </div>
        <main className="shell-main">
          <section className="panel">
            <h2>Create pool</h2>
            <p className="section-lead muted">
              Mint a new Aqua strategy with your price range and spot price at
              deposit.
            </p>
            <AddLiquidity />
          </section>
          <div className="cols trade-cols">
            <section className="panel">
              <TradeHeading />
              <Swap />
              <ReservesChart />
            </section>
            <section className="panel">
              <h2>ETH weights</h2>
              <Weights />
            </section>
          </div>
          <section className="panel panel-wide">
            <h2>History</h2>
            <History />
          </section>
        </main>
      </div>
      <PositionPop />
      <SplitModal />
      <DebugToggle />
      <Toast />
    </>
  );
}

function TradeHeading() {
  const activePoolId = useStore((s) => s.activePoolId);
  const positions = useStore((s) => s.positions);
  const active = positions.find((p) => p.id === activePoolId) ?? positions[0];
  return (
    <h2>
      Trade
      {active ? (
        <span className="h2-sub num muted">
          {" "}
          · Pool #{active.id} @ ${active.price.toFixed(4)}
        </span>
      ) : (
        <span className="h2-sub muted"> · create a pool first</span>
      )}
    </h2>
  );
}
