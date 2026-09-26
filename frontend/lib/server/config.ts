import fs from "node:fs";
import path from "node:path";
import {
  type Deployment,
  deploymentKey,
  isLocal,
  LOCAL_RPC,
} from "../config";

export type ServerConfig = {
  dep: Deployment;
  local: boolean;
  rpc: string;
  key: string;
  startBlock: number;
  logChunk: number;
  pauseMs: number;
  timeBudgetMs: number;
  confirmations: number;
};

const num = (v: string | undefined, dflt: number) => {
  const n = Number(v);
  return v != null && v !== "" && Number.isFinite(n) ? n : dflt;
};

export function loadDeployment(): Deployment {
  const file = path.join(process.cwd(), "deployments.json");
  return JSON.parse(fs.readFileSync(file, "utf8")) as Deployment;
}

export function serverConfig(): ServerConfig {
  const dep = loadDeployment();
  const local = isLocal(dep);
  const env = process.env;
  return {
    dep,
    local,
    rpc: env.INDEXER_RPC_URL || dep.rpc || LOCAL_RPC,
    key: deploymentKey(dep),
    startBlock: Number(dep.historyStartBlock ?? dep.startBlock ?? 0),
    logChunk: num(env.INDEXER_LOG_CHUNK, local ? 10_000 : 10),
    pauseMs: num(env.INDEXER_PAUSE_MS, local ? 0 : 150),
    timeBudgetMs: num(env.INDEXER_TIME_BUDGET_MS, 40_000),
    confirmations: num(env.INDEXER_CONFIRMATIONS, 0),
  };
}
