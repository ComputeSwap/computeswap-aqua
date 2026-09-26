import { ethers } from "ethers";
import { ABI, strategyTuple } from "../chain.js";
import * as C from "../curve.js";
import { type ServerConfig, serverConfig } from "./config";

export type Snapshot = {
  block: number;
  chainTime: number;
  local: boolean;
  pool: {
    initialized: boolean;
    tick?: number;
    price?: number;
    sqrtPriceX96?: string;
  };
  positions: {
    id: number;
    owner: string;
    pa: number;
    pb: number;
    price: number;
    liquidity: string;
    locked: string;
    activeSeries: number;
    eth: string;
    usdc: string;
    fees0: string;
    fees1: string;
  }[];
  auctions: {
    id: number;
    seller: string;
    startBlock: number;
    start: number;
    dropStart: number;
    end: number;
    seriesId: number;
    lot: string;
    remaining: string;
    startPrice: string;
    floorPrice: string;
  }[];
  series: { id: number; positionId: number; expiry: number }[];
  nextSeriesId: number;
  defaultSwapPositionId: number | null;
};

type Cache = {
  rpc: string;
  key: string;
  last?: { block: number; at: number; snapshot: Snapshot; promise?: undefined };
  inflight?: Promise<Snapshot>;
  seriesMeta: Map<number, { positionId: number; expiry: number }>;
  closedAuctions: Set<number>;
  deadPositions: Set<number>;
};

const g = globalThis as unknown as { __logCurveState?: Cache };
const ids = (count: number) =>
  Array.from({ length: Math.max(0, count - 1) }, (_, i) => i + 1);

function cache(cfg: ServerConfig): Cache {
  if (
    !g.__logCurveState ||
    g.__logCurveState.key !== cfg.key ||
    g.__logCurveState.rpc !== cfg.rpc
  ) {
    g.__logCurveState = {
      rpc: cfg.rpc,
      key: cfg.key,
      seriesMeta: new Map(),
      closedAuctions: new Set(),
      deadPositions: new Set(),
    };
  }
  return g.__logCurveState;
}

async function read(cfg: ServerConfig, c: Cache): Promise<Snapshot> {
  const rpc = new ethers.JsonRpcProvider(cfg.rpc, Number(cfg.dep.chainId), {
    staticNetwork: true,
    batchMaxCount: 10,
  });
  const app = new ethers.Contract(cfg.dep.app, ABI.app, rpc);
  const vault = new ethers.Contract(cfg.dep.vault, ABI.vault, rpc);
  const auction = new ethers.Contract(cfg.dep.auction, ABI.auction, rpc);

  const block = await rpc.getBlock("latest");
  if (!block) {
    throw new Error("no latest block");
  }
  let chainTime = block.timestamp;
  let blockNumber = block.number;
  if (cfg.local) {
    try {
      const pending = await rpc.send("eth_getBlockByNumber", [
        "pending",
        false,
      ]);
      chainTime = Math.max(chainTime, parseInt(pending.timestamp, 16) || 0);
      blockNumber = Math.max(blockNumber, parseInt(pending.number, 16) || 0);
    } catch {}
  }
  if (c.last && c.last.block === blockNumber) {
    return c.last.snapshot;
  }

  const [n, ns, na] = (
    await Promise.all([
      vault.nextPositionId(),
      vault.nextSeriesId(),
      auction.nextAuctionId(),
    ])
  ).map(Number);

  const positions = (
    await Promise.all(
      ids(n)
        .filter((id) => !c.deadPositions.has(id))
        .map(async (id) => {
          const row = await vault.getPosition(id);
          const pos = row.position ?? row[0];
          const owner = (row.owner ?? row[1]) as string;
          if (pos.liquidity === 0n) {
            c.deadPositions.add(id);
            return null;
          }
          let sqrtPrice = 0n;
          let active = false;
          try {
            const st = await app.states(pos.strategyHash);
            sqrtPrice = st.sqrtPriceX96;
            active = st.active;
          } catch {}
          if (!active || sqrtPrice === 0n) {
            return null;
          }
          const price = C.sqrtPriceToPrice(sqrtPrice);
          const pa = C.sqrtPriceToPrice(pos.sqrtLowerX96);
          const pb = C.sqrtPriceToPrice(pos.sqrtUpperX96);
          const strategy = strategyTuple(await vault.strategyOf(id));
          const [amount0, amount1] = await app.amountsAt(
            strategy,
            sqrtPrice,
            false,
          );
          const locked = await vault.lockedLiquidity(id);
          return {
            id,
            owner,
            pa,
            pb,
            price,
            liquidity: pos.liquidity.toString(),
            locked: locked.toString(),
            activeSeries: Number(pos.activeSeries),
            eth: amount0.toString(),
            usdc: amount1.toString(),
            fees0: "0",
            fees1: "0",
          };
        }),
    )
  ).filter((p) => p !== null);

  let pool: Snapshot["pool"] = { initialized: positions.length > 0 };
  let defaultSwapPositionId: number | null = null;
  if (positions.length > 0) {
    const primary = positions[0];
    pool = {
      initialized: true,
      price: primary.price,
      sqrtPriceX96: C.priceToSqrtPriceX96(primary.price).toString(),
    };
    defaultSwapPositionId = primary.id;
  }

  const auctions = (
    await Promise.all(
      ids(na)
        .filter((id) => !c.closedAuctions.has(id))
        .map(async (id) => {
          const a = await auction.auctions(id);
          if (a.remaining === 0n) {
            c.closedAuctions.add(id);
            return null;
          }
          return {
            id,
            seller: a.seller as string,
            startBlock: Number(a.startBlock),
            start: Number(a.start),
            dropStart: Number(a.dropStart),
            end: Number(a.end),
            seriesId: Number(a.seriesId),
            lot: a.lot.toString(),
            remaining: a.remaining.toString(),
            startPrice: a.startPrice.toString(),
            floorPrice: a.floorPrice.toString(),
          };
        }),
    )
  ).filter((a) => a !== null);

  const missing = ids(ns).filter((id) => !c.seriesMeta.has(id));
  for (let i = 0; i < missing.length; i += 10) {
    await Promise.all(
      missing.slice(i, i + 10).map(async (id) => {
        const s = await vault.series(id);
        c.seriesMeta.set(id, {
          positionId: Number(s.positionId),
          expiry: Number(s.expiry),
        });
      }),
    );
  }

  const series = ids(ns).map((id) => {
    const m = c.seriesMeta.get(id);
    return m ? { id, ...m } : { id, positionId: 0, expiry: 0 };
  });

  const snapshot: Snapshot = {
    block: blockNumber,
    chainTime,
    local: cfg.local,
    pool,
    positions,
    auctions,
    series,
    nextSeriesId: ns,
    defaultSwapPositionId,
  };
  c.last = { block: blockNumber, at: Date.now(), snapshot };
  return snapshot;
}

export async function poolState(cfg = serverConfig()): Promise<Snapshot> {
  const c = cache(cfg);
  if (!c.inflight) {
    c.inflight = read(cfg, c).finally(() => {
      c.inflight = undefined;
    });
  }
  return c.inflight;
}
