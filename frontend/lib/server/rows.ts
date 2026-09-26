import { ethers } from "ethers";
import * as C from "../curve.js";
import { fmtNum } from "../format";

export type HistoryContext = {
  price: number | null;
  ranges: Record<string, { pa: number; pb: number }>;
  seriesPos: Record<string, number>;
  auctions: Record<string, { seriesId: number; lot: bigint }>;
};

export type HistoryRow = {
  what: string;
  cls?: string;
  sub?: string;
  eth?: number | null;
  usdc?: number | null;
  price?: number | null;
};

export const emptyContext = (): HistoryContext => ({
  price: null,
  ranges: {},
  seriesPos: {},
  auctions: {},
});

const toEth = (wei: bigint) => Number(ethers.formatEther(wei));
const toUsdc = (units: bigint) => Number(ethers.formatUnits(units, 6));
const big = (v: unknown) => BigInt(v as string | number | bigint);

export function applyContext(
  H: HistoryContext,
  name: string,
  a: Record<string, unknown>,
) {
  switch (name) {
    case "Activated":
    case "Swapped":
      H.price = C.sqrtPriceToPrice(big(a.sqrtPriceX96));
      break;
    case "PositionMinted":
      break;
    case "Split":
      H.seriesPos[String(a.seriesId)] = Number(a.positionId);
      break;
    case "AuctionCreated":
      H.auctions[String(a.auctionId)] = {
        seriesId: Number(a.seriesId),
        lot: big(a.lot),
      };
      break;
  }
}

export function historyRow(
  H: HistoryContext,
  name: string,
  a: Record<string, unknown>,
): HistoryRow | null {
  const pos = (id: unknown) => (id == null ? "" : `#${id}`);
  const range = (id: string | number) =>
    H.ranges[id]
      ? `$${fmtNum(H.ranges[id].pa, 4)}–$${fmtNum(H.ranges[id].pb, 4)}`
      : "";
  const ethOf = (id: string | number | undefined, units: bigint) => {
    const r = id == null ? null : H.ranges[id];
    return r && H.price
      ? C.reserves({ ...r, L: Number(units) / 1e6 }, H.price).x
      : null;
  };
  applyContext(H, name, a);
  switch (name) {
    case "Activated":
      return { what: "Activate strategy", price: H.price };
    case "Swapped": {
      const zeroForOne = Boolean(a.zeroForOne);
      const amountIn = big(a.amountIn);
      const amountOut = big(a.amountOut);
      const eth = zeroForOne ? amountIn : amountOut;
      const usdc = zeroForOne ? amountOut : amountIn;
      return {
        what: zeroForOne ? "Sell" : "Buy",
        cls: zeroForOne ? "sell" : "buy",
        eth: toEth(eth),
        usdc: toUsdc(usdc),
        price: H.price,
      };
    }
    case "PositionMinted": {
      const id = Number(a.positionId);
      return {
        what: "Add liquidity",
        sub: `#${id}`,
        price: H.price,
      };
    }
    case "PositionRolled":
      return {
        what: "Withdraw",
        sub: `#${a.positionId}`,
        price: H.price,
      };
    case "Split": {
      const id = Number(a.positionId);
      return {
        what: "Split ETH weight",
        sub: `#${id}`,
        eth: ethOf(id, big(a.units)),
        price: H.price,
      };
    }
    case "AuctionCreated":
      return {
        what: "Open auction",
        sub: `${pos(H.seriesPos[String(a.seriesId)])} · starts at`,
        usdc: toUsdc(big(a.startPrice)),
        price: H.price,
      };
    case "Bought": {
      const auction = H.auctions[String(a.auctionId)];
      const id = auction && H.seriesPos[auction.seriesId];
      const amount = big(a.amount);
      const share = auction
        ? ` · ${fmtNum((Number(amount) / Number(auction.lot)) * 100, 1)}%`
        : "";
      return {
        what: "Buy ETH weight",
        sub: `${pos(id)}${share}`,
        eth: ethOf(id, amount),
        usdc: toUsdc(big(a.cost)),
        price: H.price,
      };
    }
    case "Cancelled": {
      const auction = H.auctions[String(a.auctionId)];
      return {
        what: "Cancel auction",
        sub: auction ? pos(H.seriesPos[auction.seriesId]) : "",
        price: H.price,
      };
    }
    case "Exercised":
      return {
        what: "Exercise",
        sub: pos(H.seriesPos[String(a.seriesId)]),
        eth: toEth(big(a.legAmount)),
        usdc: toUsdc(big(a.otherAmount)),
        price: H.price,
      };
    case "Merged":
      return {
        what: "Merge weight",
        sub: pos(H.seriesPos[String(a.seriesId)]),
        price: H.price,
      };
    default:
      return null;
  }
}
