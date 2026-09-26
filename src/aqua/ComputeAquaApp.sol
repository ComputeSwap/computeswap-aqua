// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LogCurveMath} from "../libraries/LogCurveMath.sol";
import {IAqua} from "./IAqua.sol";

interface IERC20BalanceAquaApp {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title ComputeAquaApp
/// @notice One concentrated log-curve position per Aqua strategy. Tokens stay in the maker wallet.
/// @dev ComputeSwap at ETHGlobal 2026. This is a new app; it does not modify Aqua core.
contract ComputeAquaApp is ReentrancyGuard {
    error InvalidStrategy();
    error InactiveStrategy();
    error PriceOutOfRange();
    error InsufficientOutput();
    error Slippage();
    error DeadlineExpired();
    error UnbackedStrategy();
    error NotMaker();
    error UnsupportedToken();

    event Activated(bytes32 indexed strategyHash, address indexed maker, uint160 sqrtPriceX96);
    event Retired(bytes32 indexed strategyHash);
    event Swapped(
        bytes32 indexed strategyHash,
        address indexed trader,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut,
        uint160 sqrtPriceX96
    );

    struct Strategy {
        address maker;
        address token0;
        address token1;
        uint160 sqrtLowerX96;
        uint160 sqrtUpperX96;
        uint128 liquidity;
        uint24 feeBps;
        bytes32 salt;
    }

    struct State {
        uint160 sqrtPriceX96;
        int128 emaTickWad;
        uint64 updatedAt;
        bool active;
    }

    uint256 public constant ORACLE_TIME_CONSTANT = 10 minutes;
    IAqua public immutable AQUA;
    mapping(bytes32 => State) public states;
    mapping(address => bool) private _approvedToAqua;

    constructor(IAqua aqua) {
        AQUA = aqua;
    }

    function hash(Strategy memory strategy) public pure returns (bytes32) {
        return keccak256(abi.encode(strategy));
    }

    function activate(Strategy calldata strategy, uint160 sqrtPriceX96) external nonReentrant {
        if (msg.sender != strategy.maker) revert NotMaker();
        bytes32 id = hash(strategy);
        if (states[id].active) revert InvalidStrategy();
        _validate(strategy, sqrtPriceX96, id);
        states[id] = State({
            sqrtPriceX96: sqrtPriceX96,
            emaTickWad: int128(TickMath.getTickAtSqrtPrice(sqrtPriceX96)) * 1e18,
            updatedAt: uint64(block.timestamp),
            active: true
        });
        emit Activated(id, strategy.maker, sqrtPriceX96);
    }

    /// @notice Move oracle history to a replacement strategy after a maker's dock/ship rollover.
    function activateRollover(bytes32 oldId, Strategy calldata strategy, uint160 sqrtPriceX96) external nonReentrant {
        if (msg.sender != strategy.maker) revert NotMaker();
        State storage old = states[oldId];
        if (!old.active || old.sqrtPriceX96 != sqrtPriceX96) revert InvalidStrategy();
        if (_makers[oldId] != strategy.maker) revert NotMaker();
        bytes32 newId = hash(strategy);
        if (newId == oldId || states[newId].active) revert InvalidStrategy();
        _validate(strategy, sqrtPriceX96, newId);
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        int128 ema = int128(_emaTickWad(old, tick));
        old.active = false;
        states[newId] =
            State({sqrtPriceX96: sqrtPriceX96, emaTickWad: ema, updatedAt: uint64(block.timestamp), active: true});
        emit Retired(oldId);
        emit Activated(newId, strategy.maker, sqrtPriceX96);
    }

    function retire(bytes32 id) external nonReentrant {
        State storage state = states[id];
        if (!state.active) revert InactiveStrategy();
        if (msg.sender != _makers[id]) revert NotMaker();
        state.active = false;
        emit Retired(id);
    }

    /// @dev Filled by activation so retire cannot be invoked by a different maker.
    mapping(bytes32 => address) private _makers;

    function quoteExactIn(Strategy calldata strategy, bool zeroForOne, uint256 amountIn)
        external
        view
        returns (uint256 amountOut, uint160 nextSqrtPriceX96)
    {
        return _quote(strategy, zeroForOne, amountIn);
    }

    function swapExactIn(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (to == address(0)) revert InvalidStrategy();
        bytes32 id = hash(strategy);
        State storage state = states[id];
        if (!state.active) revert InactiveStrategy();
        uint160 next;
        (amountOut, next) = _quote(strategy, zeroForOne, amountIn);
        if (amountOut < amountOutMin) revert Slippage();

        int24 oldTick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
        if (state.updatedAt != block.timestamp) {
            state.emaTickWad = int128(_emaTickWad(state, oldTick));
            state.updatedAt = uint64(block.timestamp);
        }
        state.sqrtPriceX96 = next;

        _settle(strategy, id, zeroForOne, amountIn, amountOut, to);
        emit Swapped(id, msg.sender, zeroForOne, amountIn, amountOut, next);
    }

    function _settle(
        Strategy calldata strategy,
        bytes32 id,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut,
        address to
    ) private {
        address tokenIn = zeroForOne ? strategy.token0 : strategy.token1;
        _transferInExact(tokenIn, amountIn);
        if (!_approvedToAqua[tokenIn]) {
            _approvedToAqua[tokenIn] = true;
            SafeTransferLib.safeApproveWithRetry(tokenIn, address(AQUA), type(uint256).max);
        }
        uint256 makerBefore = IERC20BalanceAquaApp(tokenIn).balanceOf(strategy.maker);
        AQUA.push(strategy.maker, address(this), id, tokenIn, amountIn);
        if (IERC20BalanceAquaApp(tokenIn).balanceOf(strategy.maker) != makerBefore + amountIn) {
            revert UnsupportedToken();
        }
        address tokenOut = zeroForOne ? strategy.token1 : strategy.token0;
        if (to == strategy.maker) revert InvalidStrategy();
        uint256 recipientBefore = IERC20BalanceAquaApp(tokenOut).balanceOf(to);
        AQUA.pull(strategy.maker, id, tokenOut, amountOut, to);
        if (IERC20BalanceAquaApp(tokenOut).balanceOf(to) != recipientBefore + amountOut) {
            revert UnsupportedToken();
        }
    }

    function _transferInExact(address token, uint256 amount) private {
        uint256 balanceBefore = IERC20BalanceAquaApp(token).balanceOf(address(this));
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        if (IERC20BalanceAquaApp(token).balanceOf(address(this)) != balanceBefore + amount) {
            revert UnsupportedToken();
        }
    }

    function getOracle(bytes32 id) external view returns (int24 tick, int24 emaTick) {
        State storage state = states[id];
        if (!state.active) revert InactiveStrategy();
        tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
        emaTick = int24(_emaTickWad(state, tick) / 1e18);
    }

    function amountsAt(Strategy calldata strategy, uint160 sqrtPriceX96, bool roundUp)
        external
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        return _amounts(strategy, sqrtPriceX96, roundUp);
    }

    function _quote(Strategy calldata strategy, bool zeroForOne, uint256 amountIn)
        private
        view
        returns (uint256 amountOut, uint160 nextSqrtPriceX96)
    {
        bytes32 id = hash(strategy);
        State storage state = states[id];
        if (!state.active) revert InactiveStrategy();
        if (amountIn == 0) revert InsufficientOutput();
        uint256 net = FullMath.mulDiv(amountIn, 10_000 - strategy.feeBps, 10_000);
        uint160 current = state.sqrtPriceX96;
        if (zeroForOne) {
            nextSqrtPriceX96 = LogCurveMath.getNextSqrtPriceFromAmount0(current, strategy.liquidity, net, true);
            if (nextSqrtPriceX96 < strategy.sqrtLowerX96) revert PriceOutOfRange();
            amountOut = LogCurveMath.getAmount1Delta(nextSqrtPriceX96, current, strategy.liquidity, false);
        } else {
            nextSqrtPriceX96 = LogCurveMath.getNextSqrtPriceFromAmount1(current, strategy.liquidity, net, true);
            if (nextSqrtPriceX96 > strategy.sqrtUpperX96) revert PriceOutOfRange();
            amountOut = LogCurveMath.getAmount0Delta(current, nextSqrtPriceX96, strategy.liquidity, false);
        }
        if (amountOut == 0) revert InsufficientOutput();
        (, uint256 balanceOut) = AQUA.safeBalances(
            strategy.maker,
            address(this),
            id,
            zeroForOne ? strategy.token0 : strategy.token1,
            zeroForOne ? strategy.token1 : strategy.token0
        );
        if (amountOut > balanceOut) revert InsufficientOutput();
    }

    function _validate(Strategy calldata strategy, uint160 price, bytes32 id) private {
        if (
            strategy.maker == address(0) || strategy.token0 == address(0) || strategy.token1 == address(0)
                || strategy.token0 == strategy.token1 || strategy.liquidity == 0 || strategy.feeBps >= 10_000
                || strategy.sqrtLowerX96 >= strategy.sqrtUpperX96 || strategy.sqrtLowerX96 > price
                || price > strategy.sqrtUpperX96
        ) revert InvalidStrategy();
        (uint256 balance0, uint256 balance1) =
            AQUA.safeBalances(strategy.maker, address(this), id, strategy.token0, strategy.token1);
        (uint256 required0, uint256 required1) = _amounts(strategy, price, true);
        if (balance0 < required0 || balance1 < required1) revert UnbackedStrategy();
        _makers[id] = strategy.maker;
    }

    function _amounts(Strategy calldata strategy, uint160 price, bool roundUp)
        private
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        amount0 = LogCurveMath.getAmount0Delta(price, strategy.sqrtUpperX96, strategy.liquidity, roundUp);
        amount1 = LogCurveMath.getAmount1Delta(strategy.sqrtLowerX96, price, strategy.liquidity, roundUp);
    }

    function _emaTickWad(State storage state, int24 tick) private view returns (int256) {
        uint256 dt = block.timestamp - state.updatedAt;
        int256 target = int256(tick) * 1e18;
        if (dt == 0) return state.emaTickWad;
        if (dt >= 40 * ORACLE_TIME_CONSTANT) return target;
        int256 decay = FixedPointMathLib.expWad(-int256(dt * 1e18 / ORACLE_TIME_CONSTANT));
        return target + (int256(state.emaTickWad) - target) * decay / 1e18;
    }
}
