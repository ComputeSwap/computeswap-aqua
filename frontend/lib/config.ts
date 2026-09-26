import { ethers } from "ethers";

export const LOCAL_RPC = "http://127.0.0.1:8546";
export const LOCAL_CHAIN_ID = 31337;

export type Deployment = {
  chainId: number;
  chainName?: string;
  rpc?: string;
  explorer?: string;
  aqua?: string;
  app: string;
  vault: string;
  weights: string;
  auction: string;
  weth: string;
  usdc: string;
  defaultFeeBps?: number;
  initPrice?: number;
  startBlock?: number;
  historyStartBlock?: number;
  usdcMintable?: boolean;
  wethMintable?: boolean;
};

export const isLocal = (dep: Deployment) =>
  Number(dep.chainId) === LOCAL_CHAIN_ID;

export function deploymentKey(dep: Deployment) {
  return `${dep.chainId}:${dep.app.toLowerCase()}`;
}
