"use client";
// Every position as a band; hover highlights one, click opens its pop-over.
import { useEffect, useRef } from "react";
import { selectPool } from "@/lib/app";
import { drawLiquidity } from "@/lib/charts.js";
import { activePosition } from "@/lib/pools";
import { useStore } from "@/lib/store";
import { useResize } from "./useResize";

type Hit = { id: number; x0: number; x1: number; y0: number; y1: number };

export default function LiquidityChart() {
  const ref = useRef<HTMLCanvasElement>(null);
  const hits = useRef<Hit[]>([]);
  const {
    positions,
    activePoolId,
    swapPreview,
    addActive,
    addGhost,
    hoverId,
    dep,
  } = useStore();
  const size = useResize();
  const active = activePosition(positions, activePoolId);
  const price =
    active?.price ?? (dep?.initPrice && dep.initPrice > 0 ? dep.initPrice : null);
  const previewPrice = swapPreview?.ok ? swapPreview.price : null;
  const ghost = addActive ? addGhost : null;
  useEffect(() => {
    if (ref.current) {
      hits.current =
        drawLiquidity(ref.current, {
          positions,
          price,
          previewPrice,
          ghost,
          hoverId,
          focusId: activePoolId ?? undefined,
        }) ?? [];
    }
  }, [positions, price, previewPrice, ghost, hoverId, activePoolId, size]);
  const hitAt = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - r.left;
    const y = e.clientY - r.top;
    return hits.current.find(
      (h) => x >= h.x0 && x <= h.x1 && y >= h.y0 && y <= h.y1,
    );
  };
  return (
    <canvas
      ref={ref}
      className="chart"
      data-pop-anchor
      style={{ cursor: "pointer" }}
      onMouseMove={(e) => {
        const id = hitAt(e)?.id;
        if (id !== useStore.getState().hoverId) {
          useStore.setState({ hoverId: id });
        }
      }}
      onMouseLeave={() => {
        if (useStore.getState().hoverId !== undefined) {
          useStore.setState({ hoverId: undefined });
        }
      }}
      onClick={(e) => {
        const hit = hitAt(e);
        if (hit && typeof hit.id === "number") {
          selectPool(hit.id);
        }
      }}
      onDoubleClick={(e) => {
        const hit = hitAt(e);
        if (hit && typeof hit.id === "number") {
          useStore.setState({
            pop: { id: hit.id, x: e.pageX, y: e.pageY },
          });
        }
      }}
    />
  );
}
