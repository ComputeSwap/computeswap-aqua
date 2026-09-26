import { ethers } from "ethers";

export { ethers };

const STRATEGY =
  "tuple(address maker, address token0, address token1, uint160 sqrtLowerX96, uint160 sqrtUpperX96, uint128 liquidity, uint24 feeBps, bytes32 salt)";

const POSITION =
  "tuple(address token0, address token1, uint160 sqrtLowerX96, uint160 sqrtUpperX96, uint128 liquidity, uint24 feeBps, uint64 nonce, uint256 activeSeries, bytes32 strategyHash)";

const ERRORS = [
  "error InvalidPosition()",
  "error NotOwnerOrApproved()",
  "error LiquidityLocked(uint128 free)",
  "error InvalidSplit()",
  "error SeriesStillActive()",
  "error SeriesExpired()",
  "error OracleDeviation(int24 tick, int24 emaTick)",
  "error Slippage()",
  "error DeadlineExpired()",
  "error UnbackedPosition()",
  "error UnsupportedToken()",
  "error InvalidStrategy()",
  "error InactiveStrategy()",
  "error PriceOutOfRange()",
  "error InsufficientOutput()",
  "error UnbackedStrategy()",
  "error NotMaker()",
  "error AnnouncementActive()",
  "error InvalidAuction()",
  "error OutlivesWeights()",
  "error NotSeller()",
  "error AuctionClosed()",
  "error TooExpensive(uint256 cost)",
  "error TransferFromFailed()",
  "error TransferFailed()",
  "error ETHTransferFailed()",
  "error MintTooLarge()",
];

export const ABI = {
  app: [
    `function hash(${STRATEGY} strategy) pure returns (bytes32)`,
    `function quoteExactIn(${STRATEGY} strategy, bool zeroForOne, uint256 amountIn) view returns (uint256 amountOut, uint160 nextSqrtPriceX96)`,
    `function swapExactIn(${STRATEGY} strategy, bool zeroForOne, uint256 amountIn, uint256 amountOutMin, address to, uint256 deadline) returns (uint256 amountOut)`,
    `function amountsAt(${STRATEGY} strategy, uint160 sqrtPriceX96, bool roundUp) pure returns (uint256 amount0, uint256 amount1)`,
    "function states(bytes32 id) view returns (uint160 sqrtPriceX96, int128 emaTickWad, uint64 updatedAt, bool active)",
    "function getOracle(bytes32 id) view returns (int24 tick, int24 emaTick)",
    "event Activated(bytes32 indexed strategyHash, address indexed maker, uint160 sqrtPriceX96)",
    "event Retired(bytes32 indexed strategyHash)",
    "event Swapped(bytes32 indexed strategyHash, address indexed trader, bool zeroForOne, uint256 amountIn, uint256 amountOut, uint160 sqrtPriceX96)",
    ...ERRORS,
  ],
  weth: [
    "function balanceOf(address) view returns (uint256)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)",
    "function mint(address to, uint256 amount)",
  ],
  usdc: [
    "function balanceOf(address) view returns (uint256)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)",
    "function mint(address to, uint256 amount)",
  ],
  vault: [
    "function mint(address token0, address token1, uint160 sqrtLowerX96, uint160 sqrtUpperX96, uint160 sqrtPriceX96, uint128 liquidity, uint24 feeBps, uint256 amount0Max, uint256 amount1Max, uint256 deadline) returns (uint256 positionId, uint256 amount0, uint256 amount1)",
    "function decreaseLiquidity(uint256 positionId, uint128 units, uint256 amount0Min, uint256 amount1Min, uint256 deadline) returns (uint256 amount0, uint256 amount1)",
    "function split(uint256 positionId, uint128 units, uint8 leg, uint64 duration) returns (uint256 seriesId)",
    "function exercise(uint256 seriesId, uint128 units, uint256 minLegAmount, uint256 deadline) returns (uint256 legAmount, uint256 otherAmount)",
    "function merge(uint256 seriesId, uint128 units)",
    "function lockedLiquidity(uint256 positionId) view returns (uint128)",
    `function getPosition(uint256 positionId) view returns (${POSITION} position, address owner)`,
    `function strategyOf(uint256 positionId) view returns (${STRATEGY})`,
    "function previewExercise(uint256 seriesId, uint128 units) view returns (uint256 legAmount, uint256 otherAmount, bool allowed, int24 tick, int24 emaTick)",
    "function series(uint256 seriesId) view returns (uint256 positionId, uint64 expiry, uint8 leg, uint128 remaining)",
    "function nextPositionId() view returns (uint256)",
    "function nextSeriesId() view returns (uint256)",
    "function maxOracleDeviation() view returns (uint24)",
    "event PositionMinted(uint256 indexed positionId, address indexed owner, bytes32 indexed strategyHash, uint128 liquidity)",
    "event PositionRolled(uint256 indexed positionId, bytes32 indexed oldHash, bytes32 indexed newHash, uint128 removed)",
    "event Split(uint256 indexed positionId, uint256 indexed seriesId, uint8 leg, uint128 units, uint64 expiry)",
    "event Exercised(uint256 indexed seriesId, address indexed holder, uint128 units, uint256 legAmount, uint256 otherAmount)",
    "event Merged(uint256 indexed seriesId, uint128 units)",
    ...ERRORS,
  ],
  weights: [
    "function balanceOf(address owner, uint256 id) view returns (uint256)",
    "function allowance(address owner, address spender, uint256 id) view returns (uint256)",
    "function approve(address spender, uint256 id, uint256 amount) returns (bool)",
    "function transfer(address to, uint256 id, uint256 amount) returns (bool)",
    "function isExpired(uint256 id) view returns (bool)",
    "function expiryOf(uint256 id) view returns (uint64)",
    ...ERRORS,
  ],
  auction: [
    "function create(uint256 seriesId, uint128 lot, address payToken, uint128 startPrice, uint128 floorPrice, uint64 dropDuration) returns (uint256 auctionId)",
    "function buy(uint256 auctionId, uint128 amount, uint256 maxCost) returns (uint256 cost)",
    "function cancel(uint256 auctionId)",
    "function currentPrice(uint256 auctionId) view returns (uint256)",
    "function quote(uint256 auctionId, uint128 amount) view returns (uint256)",
    "function quoteProtocolFee(uint256 auctionId, uint128 amount) view returns (uint256)",
    "function treasury() view returns (address)",
    "function SELLER_PREMIUM_FEE_BPS() view returns (uint256)",
    "function auctions(uint256 auctionId) view returns (address seller, uint64 startBlock, uint64 start, uint64 dropStart, uint64 end, address payToken, uint256 seriesId, uint128 lot, uint128 remaining, uint128 startPrice, uint128 floorPrice)",
    "function nextAuctionId() view returns (uint256)",
    "event AuctionCreated(uint256 indexed auctionId, address indexed seller, uint256 indexed seriesId, uint128 lot, address payToken, uint128 startPrice, uint128 floorPrice, uint64 start, uint64 startBlock, uint64 dropStart, uint64 end)",
    "event Bought(uint256 indexed auctionId, address indexed buyer, uint128 amount, uint256 cost, uint256 protocolFee)",
    "event Cancelled(uint256 indexed auctionId, uint128 returned)",
    ...ERRORS,
  ],
};

const errorInterface = new ethers.Interface(ERRORS);

const FRIENDLY = {
  DeadlineExpired: "The transaction was mined after its deadline. Try again.",
  Slippage:
    "The price moved before your transaction was mined, by more than the allowed slippage. Try again.",
  InsufficientOutput:
    "The strategy doesn't have enough balance to fill this swap.",
  PriceOutOfRange:
    "This swap would move the price outside the position's range.",
  InactiveStrategy: "This strategy is not active.",
  OracleDeviation:
    "The price moved too fast: exercising opens once it is within about 1% of its 10-minute average.",
  LiquidityLocked:
    "Part of this position is locked by its sold ETH weight until the weight expires.",
  SeriesExpired: "This ETH weight has expired.",
  SeriesStillActive: "This position already has a live ETH weight.",
  InvalidSplit:
    "Choose a share of the position above 0% and an expiry above 0.",
  AnnouncementActive:
    "The auction hasn't started yet. Wait until the price begins to fall.",
  AuctionClosed: "This auction is closed: sold out, cancelled or expired.",
  TooExpensive: "The auction price is above your limit.",
  OutlivesWeights: "The auction must end before the weight expires.",
  InvalidAuction:
    "The start price must be at least the floor price, and the auction must last some time.",
  NotSeller: "Only the seller can cancel this auction.",
  NotOwnerOrApproved: "Only the position's owner can do this.",
  InsufficientBalance: "Not enough balance.",
  TransferFromFailed:
    "A token transfer failed: check your balance and approval.",
  TransferFailed: "A token transfer failed.",
  InvalidPosition: "Invalid price range or liquidity for this position.",
  MintTooLarge: "At most 100,000 test USDC per mint.",
};

export function decodeError(err) {
  if (err?.code === "ACTION_REJECTED" || err?.info?.error?.code === 4001) {
    return "You rejected the request in your wallet.";
  }
  if (err?.code === "INSUFFICIENT_FUNDS") {
    return "Not enough ETH for this transaction and its gas.";
  }
  const msg = `${err?.shortMessage || ""} ${err?.message || ""}`.toLowerCase();
  if (msg.includes("nonce too low")) {
    return "Your wallet's transaction counter is out of date. Wait a few seconds and try again, or reset the account in MetaMask (Settings → Advanced → Clear activity tab data).";
  }
  const data = findRevertData(err);
  if (data) {
    return describe(data);
  }
  return err?.shortMessage || err?.reason || err?.message || String(err);
}

function describe(data) {
  if (!data || data === "0x") {
    return "The transaction reverted.";
  }
  try {
    const parsed = errorInterface.parseError(data);
    if (parsed) {
      const friendly = FRIENDLY[parsed.name];
      if (friendly) {
        return friendly;
      }
      return parsed.name;
    }
  } catch {}
  return "The transaction reverted.";
}

function findRevertData(err) {
  if (typeof err?.data === "string") {
    return err.data;
  }
  if (err?.error?.data) {
    return findRevertData(err.error);
  }
  if (err?.info?.error?.data) {
    return findRevertData(err.info.error);
  }
  return null;
}

export function splitDelta(delta) {
  const v = BigInt(delta);
  const sign = v < 0n ? -1n : 1n;
  const abs = v < 0n ? -v : v;
  return [sign * (abs >> 128n), sign * (abs & ((1n << 128n) - 1n))];
}
