"use client";
import { useEffect, useRef } from "react";
import { drawReserves } from "@/lib/charts.js";
import { activePosition } from "@/lib/pools";
import { useStore } from "@/lib/store";
import { useResize } from "./useResize";

export default function ReservesChart() {
  const ref = useRef<HTMLCanvasElement>(null);
  const { positions, activePoolId, swapPreview } = useStore();
  const size = useResize();
  const active = activePosition(positions, activePoolId);
  const chartPositions = active ? [active] : positions;
  const price = active?.price ?? null;
  const preview = swapPreview?.ok ? swapPreview : null;
  useEffect(() => {
    if (ref.current) {
      drawReserves(ref.current, { positions: chartPositions, price, preview });
    }
  }, [chartPositions, price, preview, size]);
  return (
    <canvas ref={ref} className="chart chart-compact" aria-label="Reserves" />
  );
}
