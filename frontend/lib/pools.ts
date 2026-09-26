import type { Deployment } from "./config";
import type { Pool, Position } from "./store";

export function activePosition(
  positions: Position[],
  activePoolId: number | null,
): Position | null {
  if (!positions.length) {
    return null;
  }
  const id = activePoolId ?? positions[0].id;
  return positions.find((p) => p.id === id) ?? positions[0];
}

export function resolveActivePoolId(
  positions: Position[],
  current: number | null,
  fallback: number | null,
): number | null {
  if (current != null && positions.some((p) => p.id === current)) {
    return current;
  }
  if (fallback != null && positions.some((p) => p.id === fallback)) {
    return fallback;
  }
  return positions[0]?.id ?? null;
}

export function poolView(
  positions: Position[],
  activePoolId: number | null,
  dep: Deployment | null,
): Pool {
  const active = activePosition(positions, activePoolId);
  if (active) {
    return { initialized: true, tick: 0, price: active.price };
  }
  const init = dep?.initPrice;
  if (init != null && init > 0) {
    return { initialized: true, tick: 0, price: init };
  }
  return { initialized: false };
}

export function canCreatePool(dep: Deployment | null, positions: Position[]) {
  if (positions.length > 0) {
    return true;
  }
  const init = dep?.initPrice;
  return init != null && init > 0;
}
