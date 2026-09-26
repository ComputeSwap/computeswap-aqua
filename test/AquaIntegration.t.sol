// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {LogCurveMath} from "../src/libraries/LogCurveMath.sol";
import {Aqua} from "aqua/src/Aqua.sol";
import {IAqua} from "../src/aqua/IAqua.sol";
import {ComputeAquaApp} from "../src/aqua/ComputeAquaApp.sol";
import {AquaWeightVault} from "../src/aqua/AquaWeightVault.sol";
import {WeightAuction} from "../src/weights/WeightAuction.sol";
import {WeightToken} from "../src/weights/WeightToken.sol";

contract TaxToken is MockERC20 {
    constructor() MockERC20("Tax Token", "TAX", 18) {}

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool ok = super.transferFrom(from, to, amount);
        _burn(to, amount / 100);
        return ok;
    }
}

/// @notice End-to-end integration against the unmodified 1inch Aqua core at lib/aqua.
///         Aqua — © Degensoft Ltd 2025.
contract AquaIntegrationTest is Test {
    Aqua internal aqua;
    ComputeAquaApp internal app;
    AquaWeightVault internal vault;
    WeightToken internal weights;
    WeightAuction internal auction;
    MockERC20 internal weth;
    MockERC20 internal usdc;

    address internal lp = makeAddr("lp");
    address internal buyer = makeAddr("buyer");
    address internal trader = makeAddr("trader");
    address internal treasury = makeAddr("treasury");

    uint128 internal constant LIQUIDITY = 100e6;
    uint160 internal lower;
    uint160 internal current;
    uint160 internal upper;
    uint256 internal positionId;

    function setUp() public {
        aqua = new Aqua();
        app = new ComputeAquaApp(IAqua(address(aqua)));
        vault = new AquaWeightVault(app, 100);
        weights = vault.weights();
        auction = new WeightAuction(weights, treasury);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        lower = _sqrtAt(0.5e18);
        current = _sqrtAt(1e18);
        upper = _sqrtAt(2e18);
        weth.mint(lp, 1_000 ether);
        usdc.mint(lp, 1_000e6);
        weth.mint(trader, 1_000 ether);
        usdc.mint(trader, 1_000e6);
        usdc.mint(buyer, 1_000e6);
        vm.startPrank(lp);
        weth.approve(address(vault), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        weights.setOperator(address(auction), true);
        (positionId,,) = vault.mint(
            address(weth),
            address(usdc),
            lower,
            upper,
            current,
            LIQUIDITY,
            30,
            type(uint256).max,
            type(uint256).max,
            block.timestamp
        );
        vm.stopPrank();
        vm.startPrank(trader);
        weth.approve(address(app), type(uint256).max);
        usdc.approve(address(app), type(uint256).max);
        vm.stopPrank();
        vm.prank(buyer);
        usdc.approve(address(auction), type(uint256).max);
    }

    function test_realAquaShipSwapAndWithdraw() public {
        ComputeAquaApp.Strategy memory strategy = vault.strategyOf(positionId);
        bytes32 id = app.hash(strategy);
        (uint256 virtual0, uint256 virtual1) =
            aqua.safeBalances(address(vault), address(app), id, address(weth), address(usdc));
        assertEq(virtual0, weth.balanceOf(address(vault)));
        assertEq(virtual1, usdc.balanceOf(address(vault)));

        (uint256 expectedOut, uint160 next) = app.quoteExactIn(strategy, true, 1 ether);
        uint256 traderUSDC = usdc.balanceOf(trader);
        vm.prank(trader);
        uint256 actualOut = app.swapExactIn(strategy, true, 1 ether, expectedOut, trader, block.timestamp);
        assertEq(actualOut, expectedOut);
        assertEq(usdc.balanceOf(trader) - traderUSDC, expectedOut);
        (uint160 price,,,) = app.states(id);
        assertEq(price, next);
        (virtual0, virtual1) = aqua.safeBalances(address(vault), address(app), id, address(weth), address(usdc));
        assertEq(virtual0, weth.balanceOf(address(vault)));
        assertEq(virtual1, usdc.balanceOf(address(vault)));

        vm.prank(lp);
        (uint256 withdrawn0, uint256 withdrawn1) = vault.decreaseLiquidity(positionId, LIQUIDITY, 0, 0, block.timestamp);
        assertEq(withdrawn0, virtual0);
        assertEq(withdrawn1, virtual1);
        assertEq(weth.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(address(vault)), 0);
        (uint248 oldBalance, uint8 tokenCount) = aqua.rawBalances(address(vault), address(app), id, address(weth));
        assertEq(oldBalance, 0);
        assertEq(tokenCount, type(uint8).max); // Aqua's docked marker
    }

    function test_auctionPartialExerciseRolloverAndFinalExercise() public {
        vm.prank(lp);
        uint256 seriesId = vault.split(positionId, LIQUIDITY, 0, 2 days);
        vm.prank(lp);
        uint256 auctionId = auction.create(seriesId, LIQUIDITY, address(usdc), 20e6, 5e6, 1 hours);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 30 minutes);
        {
            uint256 cost = auction.quote(auctionId, LIQUIDITY);
            uint256 protocolFee = auction.quoteProtocolFee(auctionId, LIQUIDITY);
            uint256 sellerBefore = usdc.balanceOf(lp);
            vm.prank(buyer);
            auction.buy(auctionId, LIQUIDITY, cost);
            assertEq(usdc.balanceOf(lp) - sellerBefore, cost - protocolFee);
            assertEq(usdc.balanceOf(treasury), protocolFee);
        }

        bytes32 oldId;
        {
            ComputeAquaApp.Strategy memory original = vault.strategyOf(positionId);
            oldId = app.hash(original);
            vm.prank(trader);
            app.swapExactIn(original, true, 20 ether, 0, trader, block.timestamp);
        }
        vm.prank(buyer);
        vm.expectRevert();
        vault.exercise(seriesId, LIQUIDITY / 2, 0, block.timestamp);

        vm.warp(block.timestamp + 1 hours);
        {
            (uint256 expectedLeg,, bool allowed,,) = vault.previewExercise(seriesId, LIQUIDITY / 2);
            assertTrue(allowed);
            uint256 buyerBefore = weth.balanceOf(buyer);
            vm.prank(buyer);
            (uint256 leg,) = vault.exercise(seriesId, LIQUIDITY / 2, expectedLeg, block.timestamp);
            assertEq(leg, expectedLeg);
            assertEq(weth.balanceOf(buyer) - buyerBefore, leg);
            (AquaWeightVault.Position memory p,) = vault.getPosition(positionId);
            assertEq(p.liquidity, LIQUIDITY / 2);
            assertTrue(p.strategyHash != oldId);
            (uint248 oldBalance, uint8 tokenCount) =
                aqua.rawBalances(address(vault), address(app), oldId, address(weth));
            assertEq(oldBalance, 0);
            assertEq(tokenCount, type(uint8).max);
            (uint256 newBalance0, uint256 newBalance1) =
                aqua.safeBalances(address(vault), address(app), p.strategyHash, address(weth), address(usdc));
            assertGe(weth.balanceOf(address(vault)), newBalance0);
            assertGe(usdc.balanceOf(address(vault)), newBalance1);
        }

        ComputeAquaApp.Strategy memory nextStrategy = vault.strategyOf(positionId);
        vm.prank(trader);
        app.swapExactIn(nextStrategy, false, 1e6, 0, trader, block.timestamp);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(buyer);
        vault.exercise(seriesId, LIQUIDITY / 2, 0, block.timestamp);
        (AquaWeightVault.Position memory finalPosition,) = vault.getPosition(positionId);
        assertEq(finalPosition.liquidity, 0);
        assertEq(vault.lockedLiquidity(positionId), 0);
        assertEq(weights.balanceOf(buyer, seriesId), 0);
    }

    function test_expiryReturnsUnsoldWeightToLp() public {
        vm.prank(lp);
        uint256 seriesId = vault.split(positionId, LIQUIDITY, 0, 2 hours);
        vm.prank(lp);
        uint256 auctionId = auction.create(seriesId, LIQUIDITY, address(usdc), 20e6, 5e6, 1 hours);
        vm.warp(block.timestamp + 2 hours);
        assertEq(vault.lockedLiquidity(positionId), 0);
        vm.prank(lp);
        auction.cancel(auctionId);
        vm.prank(lp);
        vault.decreaseLiquidity(positionId, LIQUIDITY, 0, 0, block.timestamp);
        (AquaWeightVault.Position memory p,) = vault.getPosition(positionId);
        assertEq(p.liquidity, 0);
    }

    function test_otherMakerCannotRetireStrategyThroughRollover() public {
        ComputeAquaApp.Strategy memory rogue = vault.strategyOf(positionId);
        bytes32 liveId = app.hash(rogue);
        rogue.maker = buyer;
        rogue.salt = keccak256("rogue");
        vm.prank(buyer);
        vm.expectRevert(ComputeAquaApp.NotMaker.selector);
        app.activateRollover(liveId, rogue, current);
        (,,, bool active) = app.states(liveId);
        assertTrue(active);
    }

    function test_twoPositionsCannotReuseTheSameVaultFunds() public {
        (AquaWeightVault.Position memory first,) = vault.getPosition(positionId);
        (uint256 first0, uint256 first1) =
            aqua.safeBalances(address(vault), address(app), first.strategyHash, address(weth), address(usdc));
        vm.prank(lp);
        (uint256 secondId,,) = vault.mint(
            address(weth),
            address(usdc),
            lower,
            upper,
            current,
            LIQUIDITY,
            30,
            type(uint256).max,
            type(uint256).max,
            block.timestamp
        );
        (AquaWeightVault.Position memory second,) = vault.getPosition(secondId);
        (uint256 second0, uint256 second1) =
            aqua.safeBalances(address(vault), address(app), second.strategyHash, address(weth), address(usdc));
        assertTrue(first.strategyHash != second.strategyHash);
        assertEq(weth.balanceOf(address(vault)), first0 + second0);
        assertEq(usdc.balanceOf(address(vault)), first1 + second1);

        ComputeAquaApp.Strategy memory firstStrategy = vault.strategyOf(positionId);
        vm.prank(trader);
        app.swapExactIn(firstStrategy, true, 1 ether, 0, trader, block.timestamp);
        (first0, first1) =
            aqua.safeBalances(address(vault), address(app), first.strategyHash, address(weth), address(usdc));
        assertEq(weth.balanceOf(address(vault)), first0 + second0);
        assertEq(usdc.balanceOf(address(vault)), first1 + second1);
    }

    function test_feeOnTransferTokenRejectedBeforeShipping() public {
        TaxToken tax = new TaxToken();
        tax.mint(lp, 1_000 ether);
        vm.startPrank(lp);
        tax.approve(address(vault), type(uint256).max);
        vm.expectRevert(AquaWeightVault.UnsupportedToken.selector);
        vault.mint(
            address(tax),
            address(usdc),
            lower,
            upper,
            current,
            LIQUIDITY,
            30,
            type(uint256).max,
            type(uint256).max,
            block.timestamp
        );
        vm.stopPrank();
        assertEq(vault.nextPositionId(), 2);
    }

    function test_rolloverAtBothRangeBoundaries() public {
        uint160 tightUpper = LogCurveMath.getNextSqrtPriceFromAmount1(current, LIQUIDITY, 997_000, true);
        vm.prank(lp);
        (uint256 upperId,,) = vault.mint(
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
        ComputeAquaApp.Strategy memory upperStrategy = vault.strategyOf(upperId);
        vm.prank(trader);
        app.swapExactIn(upperStrategy, false, 1e6, 0, trader, block.timestamp);
        (uint160 upperPrice,,,) = app.states(app.hash(upperStrategy));
        assertEq(upperPrice, tightUpper);
        vm.prank(lp);
        vault.decreaseLiquidity(upperId, LIQUIDITY / 2, 0, 0, block.timestamp);
        (AquaWeightVault.Position memory upperPosition,) = vault.getPosition(upperId);
        assertEq(upperPosition.liquidity, LIQUIDITY / 2);

        uint160 tightLower = LogCurveMath.getNextSqrtPriceFromAmount0(current, LIQUIDITY, 0.997 ether, true);
        vm.prank(lp);
        (uint256 lowerId,,) = vault.mint(
            address(weth),
            address(usdc),
            tightLower,
            upper,
            current,
            LIQUIDITY,
            30,
            type(uint256).max,
            type(uint256).max,
            block.timestamp
        );
        ComputeAquaApp.Strategy memory lowerStrategy = vault.strategyOf(lowerId);
        vm.prank(trader);
        app.swapExactIn(lowerStrategy, true, 1 ether, 0, trader, block.timestamp);
        (uint160 lowerPrice,,,) = app.states(app.hash(lowerStrategy));
        assertEq(lowerPrice, tightLower);
        vm.prank(lp);
        vault.decreaseLiquidity(lowerId, LIQUIDITY / 2, 0, 0, block.timestamp);
        (AquaWeightVault.Position memory lowerPosition,) = vault.getPosition(lowerId);
        assertEq(lowerPosition.liquidity, LIQUIDITY / 2);
    }

    function test_lpWithdrawalCannotResetExerciseOracle() public {
        vm.prank(lp);
        uint256 seriesId = vault.split(positionId, LIQUIDITY / 2, 0, 2 days);
        vm.prank(lp);
        weights.transfer(buyer, seriesId, LIQUIDITY / 2);
        ComputeAquaApp.Strategy memory oldStrategy = vault.strategyOf(positionId);
        vm.prank(trader);
        app.swapExactIn(oldStrategy, true, 20 ether, 0, trader, block.timestamp);
        (int24 oldTick, int24 oldEma) = app.getOracle(app.hash(oldStrategy));
        assertGt(int256(oldEma) - int256(oldTick), 100);

        vm.prank(lp);
        vault.decreaseLiquidity(positionId, LIQUIDITY / 4, 0, 0, block.timestamp);
        ComputeAquaApp.Strategy memory newStrategy = vault.strategyOf(positionId);
        (int24 newTick, int24 newEma) = app.getOracle(app.hash(newStrategy));
        assertEq(newTick, oldTick);
        assertEq(newEma, oldEma);
        vm.prank(buyer);
        vm.expectRevert();
        vault.exercise(seriesId, LIQUIDITY / 4, 0, block.timestamp);
    }

    function test_otherLegFollowsTransferredLpNft() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(lp);
        uint256 seriesId = vault.split(positionId, LIQUIDITY / 2, 0, 2 days);
        vm.prank(lp);
        weights.transfer(buyer, seriesId, LIQUIDITY / 2);
        vm.prank(lp);
        vault.transferFrom(lp, newOwner, positionId);
        uint256 oldOwnerUSDC = usdc.balanceOf(lp);
        uint256 newOwnerUSDC = usdc.balanceOf(newOwner);
        vm.prank(buyer);
        (, uint256 other) = vault.exercise(seriesId, LIQUIDITY / 2, 0, block.timestamp);
        assertEq(usdc.balanceOf(lp), oldOwnerUSDC);
        assertEq(usdc.balanceOf(newOwner) - newOwnerUSDC, other);
    }

    function testFuzz_aquaBackingAcrossSwapsAndPartialWithdrawals(uint96 seed) public {
        for (uint256 i; i < 8; ++i) {
            ComputeAquaApp.Strategy memory strategy = vault.strategyOf(positionId);
            bool zeroForOne = (uint256(seed) >> i) & 1 == 1;
            uint256 amountIn = zeroForOne
                ? (uint256((seed >> (i + 8)) % 5) + 1) * 0.1 ether
                : (uint256((seed >> (i + 8)) % 5) + 1) * 100_000;
            vm.prank(trader);
            app.swapExactIn(strategy, zeroForOne, amountIn, 0, trader, block.timestamp);
            if (i % 2 == 1) {
                vm.prank(lp);
                vault.decreaseLiquidity(positionId, LIQUIDITY / 16, 0, 0, block.timestamp);
            }
            (AquaWeightVault.Position memory p,) = vault.getPosition(positionId);
            (uint256 balance0, uint256 balance1) =
                aqua.safeBalances(address(vault), address(app), p.strategyHash, address(weth), address(usdc));
            assertEq(weth.balanceOf(address(vault)), balance0);
            assertEq(usdc.balanceOf(address(vault)), balance1);
            (uint160 price,,,) = app.states(p.strategyHash);
            (uint256 required0, uint256 required1) = app.amountsAt(vault.strategyOf(positionId), price, true);
            assertGe(balance0, required0);
            assertGe(balance1, required1);
        }
    }

    function _sqrtAt(uint256 humanPriceWad) private pure returns (uint160) {
        return uint160(FullMath.mulDiv(FixedPointMathLib.sqrt(humanPriceWad * 1e18), 1 << 96, 1e24));
    }
}
