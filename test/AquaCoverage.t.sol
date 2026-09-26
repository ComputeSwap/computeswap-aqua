// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.30;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {LogCurveMath} from "../src/libraries/LogCurveMath.sol";
import {Aqua} from "aqua/src/Aqua.sol";
import {IAqua} from "../src/aqua/IAqua.sol";
import {ComputeAquaApp} from "../src/aqua/ComputeAquaApp.sol";
import {AquaWeightVault} from "../src/aqua/AquaWeightVault.sol";
import {WeightAuction} from "../src/weights/WeightAuction.sol";
import {WeightToken} from "../src/weights/WeightToken.sol";
import {AquaFixture} from "./utils/AquaFixture.sol";

contract USDCWithBlockedRecipient is MockERC20 {
    address public blockedRecipient;

    constructor() MockERC20("USD Coin", "USDC", 6) {}

    function setBlockedRecipient(address account) external {
        blockedRecipient = account;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (to == blockedRecipient) return false;
        return super.transfer(to, amount);
    }
}

contract AquaCoverageTest is AquaFixture {
    function setUp() public {
        setUpAqua();
    }

    function test_mergeUnlocksLiquidityWithoutExercise() public {
        vm.prank(lp);
        uint256 seriesId = vault.split(positionId, LIQUIDITY / 2, 0, 2 days);
        assertEq(vault.lockedLiquidity(positionId), LIQUIDITY / 2);
        vm.prank(lp);
        vault.merge(seriesId, LIQUIDITY / 4);
        assertEq(vault.lockedLiquidity(positionId), LIQUIDITY / 4);
        uint128 free = LIQUIDITY - LIQUIDITY / 4;
        vm.prank(lp);
        vault.decreaseLiquidity(positionId, free, 0, 0, block.timestamp);
        (AquaWeightVault.Position memory p,) = vault.getPosition(positionId);
        assertEq(p.liquidity, LIQUIDITY / 4);
    }

    function test_claimWhenUsdcPayoutBlocked() public {
        USDCWithBlockedRecipient blockedUsdc = new USDCWithBlockedRecipient();
        Aqua aquaLocal = new Aqua();
        ComputeAquaApp appLocal = new ComputeAquaApp(IAqua(address(aquaLocal)));
        AquaWeightVault vaultLocal = new AquaWeightVault(appLocal, 100);
        MockERC20 wethLocal = new MockERC20("Wrapped ETH", "WETH", 18);
        address blockedOwner = makeAddr("blockedOwner");
        blockedUsdc.setBlockedRecipient(blockedOwner);
        wethLocal.mint(lp, 1_000 ether);
        blockedUsdc.mint(lp, 1_000e6);
        vm.startPrank(lp);
        wethLocal.approve(address(vaultLocal), type(uint256).max);
        blockedUsdc.approve(address(vaultLocal), type(uint256).max);
        (uint256 localPosition,,) = vaultLocal.mint(
            address(wethLocal),
            address(blockedUsdc),
            lower,
            upper,
            current,
            LIQUIDITY,
            30,
            type(uint256).max,
            type(uint256).max,
            block.timestamp
        );
        uint256 seriesId = vaultLocal.split(localPosition, LIQUIDITY / 2, 0, 2 days);
        WeightToken localWeights = vaultLocal.weights();
        localWeights.transfer(buyer, seriesId, LIQUIDITY / 2);
        vaultLocal.transferFrom(lp, blockedOwner, localPosition);
        vm.stopPrank();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(buyer);
        vaultLocal.exercise(seriesId, LIQUIDITY / 2, 0, block.timestamp);
        assertGt(vaultLocal.owed(blockedOwner, address(blockedUsdc)), 0);
        uint256 credited = vaultLocal.owed(blockedOwner, address(blockedUsdc));
        address payoutSink = makeAddr("payoutSink");
        vm.prank(blockedOwner);
        uint256 claimed = vaultLocal.claim(address(blockedUsdc), payoutSink);
        assertEq(claimed, credited);
        assertEq(blockedUsdc.balanceOf(payoutSink), credited);
        assertEq(vaultLocal.owed(blockedOwner, address(blockedUsdc)), 0);
    }

    function test_exerciseUsdcLegPaysBuyerUsdc() public {
        vm.prank(lp);
        uint256 seriesId = vault.split(positionId, LIQUIDITY / 2, 1, 2 days);
        vm.prank(lp);
        weights.transfer(buyer, seriesId, LIQUIDITY / 2);
        vm.warp(block.timestamp + 1 hours);
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);
        uint256 lpWethBefore = weth.balanceOf(lp);
        vm.prank(buyer);
        (uint256 legUsdc, uint256 otherWeth) = vault.exercise(seriesId, LIQUIDITY / 2, 0, block.timestamp);
        assertGt(legUsdc, 0);
        assertGt(otherWeth, 0);
        assertEq(usdc.balanceOf(buyer) - buyerUsdcBefore, legUsdc);
        assertGe(weth.balanceOf(lp) - lpWethBefore, otherWeth);
    }

    function test_swapRevertsPriceOutOfRangePastUpper() public {
        uint160 tightUpper = LogCurveMath.getNextSqrtPriceFromAmount1(current, LIQUIDITY, 997_000, true);
        vm.prank(lp);
        (uint256 pid,,) = vault.mint(
            address(weth),
            address(usdc),
            lower,
            tightUpper,
            current,
            LIQUIDITY,
            30,
            type(uint256).max,
            type(uint256).max,
            block.timestamp
        );
        ComputeAquaApp.Strategy memory strategy = vault.strategyOf(pid);
        vm.prank(trader);
        app.swapExactIn(strategy, false, 997_000, 0, trader, block.timestamp);
        vm.prank(trader);
        vm.expectRevert(ComputeAquaApp.PriceOutOfRange.selector);
        app.swapExactIn(strategy, false, 500_000, 0, trader, block.timestamp);
    }

    function test_swapRevertsZeroInputInsufficientOutput() public {
        ComputeAquaApp.Strategy memory strategy = vault.strategyOf(positionId);
        vm.prank(trader);
        vm.expectRevert(ComputeAquaApp.InsufficientOutput.selector);
        app.swapExactIn(strategy, true, 0, 0, trader, block.timestamp);
    }

    function test_swapRevertsSlippageAndDeadline() public {
        ComputeAquaApp.Strategy memory strategy = vault.strategyOf(positionId);
        (uint256 out,) = app.quoteExactIn(strategy, true, 1 ether);
        vm.prank(trader);
        vm.expectRevert(ComputeAquaApp.Slippage.selector);
        app.swapExactIn(strategy, true, 1 ether, out + 1, trader, block.timestamp);
        vm.prank(trader);
        vm.expectRevert(ComputeAquaApp.DeadlineExpired.selector);
        app.swapExactIn(strategy, true, 1 ether, 0, trader, block.timestamp - 1);
    }

    function test_partialWithdrawProRataFeesMatchFormula() public {
        ComputeAquaApp.Strategy memory strategy = vault.strategyOf(positionId);
        bytes32 id = app.hash(strategy);
        vm.prank(trader);
        app.swapExactIn(strategy, true, 1 ether, 0, trader, block.timestamp);
        (uint160 price,,,) = app.states(id);
        (uint256 balance0, uint256 balance1) =
            aqua.safeBalances(address(vault), address(app), id, address(weth), address(usdc));
        (uint256 principal0, uint256 principal1) = app.amountsAt(strategy, price, true);
        uint128 units = LIQUIDITY / 4;
        uint256 expectedFee0 = FullMath.mulDiv(balance0 - principal0, units, LIQUIDITY);
        uint256 expectedFee1 = FullMath.mulDiv(balance1 - principal1, units, LIQUIDITY);
        ComputeAquaApp.Strategy memory remainder = strategy;
        remainder.liquidity = LIQUIDITY - units;
        (uint256 remPrincipal0, uint256 remPrincipal1) = app.amountsAt(remainder, price, true);
        uint256 expectedPrincipal0 = principal0 - remPrincipal0;
        uint256 expectedPrincipal1 = principal1 - remPrincipal1;
        vm.prank(lp);
        (uint256 out0, uint256 out1) = vault.decreaseLiquidity(positionId, units, 0, 0, block.timestamp);
        assertEq(out0, expectedPrincipal0 + expectedFee0);
        assertEq(out1, expectedPrincipal1 + expectedFee1);
    }

    function test_auctionPartialFillAndPriceDecay() public {
        vm.prank(lp);
        uint256 seriesId = vault.split(positionId, LIQUIDITY, 0, 2 days);
        vm.prank(lp);
        uint256 auctionId = auction.create(seriesId, LIQUIDITY, address(usdc), 20e6, 5e6, 1 hours);
        vm.roll(block.number + 1);
        uint128 half = LIQUIDITY / 2;
        uint256 priceMid = auction.currentPrice(auctionId);
        vm.warp(block.timestamp + 30 minutes);
        assertLt(auction.currentPrice(auctionId), priceMid);
        uint256 costHalf = auction.quote(auctionId, half);
        vm.prank(buyer);
        auction.buy(auctionId, half, costHalf);
        assertEq(_auctionRemaining(auctionId), half);
        assertEq(weights.balanceOf(buyer, seriesId), half);
        uint256 costRest = auction.quote(auctionId, half);
        vm.prank(buyer2);
        auction.buy(auctionId, half, costRest);
        assertEq(_auctionRemaining(auctionId), 0);
        assertEq(weights.balanceOf(buyer2, seriesId), half);
    }

    function test_auctionRevertPaths() public {
        vm.prank(lp);
        uint256 seriesId = vault.split(positionId, LIQUIDITY / 2, 0, 1 hours);
        vm.expectRevert(WeightAuction.InvalidAuction.selector);
        auction.create(seriesId, 0, address(usdc), 10e6, 5e6, 1 hours);
        vm.expectRevert(WeightAuction.InvalidAuction.selector);
        auction.create(seriesId, 1, address(usdc), 10e6, 5e6, 0);
        vm.expectRevert(WeightAuction.InvalidAuction.selector);
        auction.create(seriesId, LIQUIDITY / 4, address(usdc), 5e6, 10e6, 1 hours);
        vm.expectRevert(WeightAuction.OutlivesWeights.selector);
        auction.create(seriesId, LIQUIDITY / 4, address(usdc), 10e6, 5e6, 2 hours);
        vm.prank(lp);
        uint256 auctionId = auction.create(seriesId, LIQUIDITY / 4, address(usdc), 10e6, 5e6, 30 minutes);
        vm.prank(buyer);
        vm.expectRevert(WeightAuction.AnnouncementActive.selector);
        auction.buy(auctionId, 1, type(uint256).max);
        vm.roll(block.number + 1);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(WeightAuction.TooExpensive.selector, auction.quote(auctionId, 1)));
        auction.buy(auctionId, 1, 0);
        vm.prank(stranger);
        vm.expectRevert(WeightAuction.NotSeller.selector);
        auction.cancel(auctionId);
    }

    function test_weightTokenExpiredBalanceAndTransfer() public {
        vm.prank(lp);
        uint256 seriesId = vault.split(positionId, LIQUIDITY / 4, 0, 1 hours);
        assertEq(weights.balanceOf(lp, seriesId), LIQUIDITY / 4);
        vm.warp(block.timestamp + 1 hours);
        assertTrue(weights.isExpired(seriesId));
        assertEq(weights.balanceOf(lp, seriesId), 0);
        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(WeightToken.SeriesExpired.selector, seriesId));
        weights.transfer(buyer, seriesId, 1);
    }

    function test_vaultAccessControlReverts() public {
        vm.prank(stranger);
        vm.expectRevert(AquaWeightVault.NotOwnerOrApproved.selector);
        vault.decreaseLiquidity(positionId, 1, 0, 0, block.timestamp);
        vm.prank(lp);
        uint256 seriesId = vault.split(positionId, LIQUIDITY / 2, 0, 2 days);
        vm.prank(lp);
        vm.expectRevert(AquaWeightVault.SeriesStillActive.selector);
        vault.split(positionId, 1, 0, 1 days);
        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(AquaWeightVault.LiquidityLocked.selector, LIQUIDITY / 2));
        vault.decreaseLiquidity(positionId, LIQUIDITY, 0, 0, block.timestamp);
        vm.prank(lp);
        vault.merge(seriesId, LIQUIDITY / 2);
    }

    function test_retireNotMakerAndInactiveSwap() public {
        ComputeAquaApp.Strategy memory strategy = vault.strategyOf(positionId);
        bytes32 id = app.hash(strategy);
        vm.prank(trader);
        vm.expectRevert(ComputeAquaApp.NotMaker.selector);
        app.retire(id);
        vm.prank(lp);
        vault.decreaseLiquidity(positionId, LIQUIDITY, 0, 0, block.timestamp);
        (,,, bool active) = app.states(id);
        assertFalse(active);
        vm.prank(trader);
        vm.expectRevert(ComputeAquaApp.InactiveStrategy.selector);
        app.swapExactIn(strategy, true, 1 ether, 0, trader, block.timestamp);
    }

    function _auctionRemaining(uint256 auctionId) internal view returns (uint128 remaining) {
        (,,,,,,,, remaining,,) = auction.auctions(auctionId);
    }
}
