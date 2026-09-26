// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Aqua} from "aqua/src/Aqua.sol";
import {IAqua} from "../../src/aqua/IAqua.sol";
import {ComputeAquaApp} from "../../src/aqua/ComputeAquaApp.sol";
import {AquaWeightVault} from "../../src/aqua/AquaWeightVault.sol";
import {WeightAuction} from "../../src/weights/WeightAuction.sol";
import {WeightToken} from "../../src/weights/WeightToken.sol";

abstract contract AquaFixture is Test {
    Aqua internal aqua;
    ComputeAquaApp internal app;
    AquaWeightVault internal vault;
    WeightToken internal weights;
    WeightAuction internal auction;
    MockERC20 internal weth;
    MockERC20 internal usdc;

    address internal lp = makeAddr("lp");
    address internal buyer = makeAddr("buyer");
    address internal buyer2 = makeAddr("buyer2");
    address internal trader = makeAddr("trader");
    address internal stranger = makeAddr("stranger");
    address internal treasury = makeAddr("treasury");

    uint128 internal constant LIQUIDITY = 100e6;
    uint160 internal lower;
    uint160 internal current;
    uint160 internal upper;
    uint256 internal positionId;

    function setUpAqua() internal {
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
        usdc.mint(buyer2, 1_000e6);
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
        vm.prank(buyer2);
        usdc.approve(address(auction), type(uint256).max);
    }

    function _sqrtAt(uint256 humanPriceWad) internal pure returns (uint160) {
        return uint160(FullMath.mulDiv(FixedPointMathLib.sqrt(humanPriceWad * 1e18), 1 << 96, 1e24));
    }
}
