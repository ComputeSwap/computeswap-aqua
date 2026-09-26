// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {LogCurveMath} from "../src/libraries/LogCurveMath.sol";

contract LogCurveMathTest is Test {
    uint128 internal constant L = 100e6;

    function _sqrtAt(uint256 humanPriceWad) internal pure returns (uint160) {
        return uint160(FullMath.mulDiv(FixedPointMathLib.sqrt(humanPriceWad * 1e18), 1 << 96, 1e24));
    }

    function test_amount0DeltaRoundUpGeRoundDown() public pure {
        uint160 lo = _sqrtAt(0.5e18);
        uint160 hi = _sqrtAt(2e18);
        assertGe(LogCurveMath.getAmount0Delta(lo, hi, L, true), LogCurveMath.getAmount0Delta(lo, hi, L, false));
    }

    function test_amount1DeltaRoundUpGeRoundDown() public pure {
        uint160 lo = _sqrtAt(0.5e18);
        uint160 hi = _sqrtAt(2e18);
        assertGe(LogCurveMath.getAmount1Delta(lo, hi, L, true), LogCurveMath.getAmount1Delta(lo, hi, L, false));
    }

    function test_ethInLowersSqrtPriceUsdcInRaises() public pure {
        uint160 p = _sqrtAt(1e18);
        uint160 lo = _sqrtAt(0.5e18);
        uint160 hi = _sqrtAt(2e18);
        uint160 afterEth = LogCurveMath.getNextSqrtPriceFromAmount0(p, L, 0.1 ether, true);
        assertLt(afterEth, p);
        assertGe(afterEth, lo);
        uint160 afterUsdc = LogCurveMath.getNextSqrtPriceFromAmount1(p, L, 100_000, true);
        assertGt(afterUsdc, p);
        assertLe(afterUsdc, hi);
    }

    function test_swapStepAmount1OutMatchesDelta() public pure {
        uint160 p = _sqrtAt(1e18);
        uint160 hi = _sqrtAt(2e18);
        uint256 dx = 0.25 ether;
        uint160 p2 = LogCurveMath.getNextSqrtPriceFromAmount0(p, L, dx, true);
        uint256 dy = LogCurveMath.getAmount1Delta(p2, p, L, false);
        assertGt(dy, 0);
        assertLe(p2, hi);
    }

    function testFuzz_swap0StepStaysInRange(uint128 dx) public pure {
        dx = uint128(bound(dx, 1, 2 ether));
        uint160 p = _sqrtAt(1e18);
        uint160 lo = _sqrtAt(0.5e18);
        uint160 hi = _sqrtAt(2e18);
        uint160 p2 = LogCurveMath.getNextSqrtPriceFromAmount0(p, L, dx, true);
        if (p2 < lo) return;
        assertLe(p2, p);
        uint256 dy = LogCurveMath.getAmount1Delta(p2, p, L, false);
        if (dy == 0) return;
        assertLe(p2, hi);
    }
}
