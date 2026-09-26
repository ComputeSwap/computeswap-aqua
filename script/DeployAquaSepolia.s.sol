// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IAqua} from "../src/aqua/IAqua.sol";
import {ComputeAquaApp} from "../src/aqua/ComputeAquaApp.sol";
import {AquaWeightVault} from "../src/aqua/AquaWeightVault.sol";
import {WeightAuction} from "../src/weights/WeightAuction.sol";
import {LogCurveMath} from "../src/libraries/LogCurveMath.sol";

interface IWETH9 {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IERC20Mintable {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract DeployAquaSepolia is Script {
    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address internal constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address internal constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    function run() external {
        address aquaAddress = vm.envOr("AQUA_ADDRESS", AQUA);
        address weth = vm.envOr("WETH_ADDRESS", WETH);
        address usdc = vm.envOr("USDC_ADDRESS", USDC);
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        bool seed = vm.envOr("SEED_POSITION", false);
        uint256 initUsd = vm.envOr("INIT_PRICE_USD", uint256(3000));
        require(aquaAddress.code.length != 0, "Aqua core not deployed on this chain");
        require(weth.code.length != 0, "WETH missing");
        require(usdc.code.length != 0, "USDC missing");
        require(treasury != address(0), "TREASURY_ADDRESS required");
        vm.startBroadcast(deployerKey);
        ComputeAquaApp app = new ComputeAquaApp(IAqua(aquaAddress));
        AquaWeightVault vault = new AquaWeightVault(app, 100);
        WeightAuction auction = new WeightAuction(vault.weights(), treasury);
        uint256 positionId;
        if (seed) {
            positionId = _seed(vault, weth, usdc, deployer, initUsd);
        }
        vm.stopBroadcast();
        _writeJson(app, vault, auction, aquaAddress, weth, usdc, initUsd);
        console2.log("Aqua", aquaAddress);
        console2.log("ComputeAquaApp", address(app));
        console2.log("AquaWeightVault", address(vault));
        console2.log("WeightAuction", address(auction));
        console2.log("WETH", weth);
        console2.log("USDC", usdc);
        if (seed) {
            console2.log("Initial position ID", positionId);
        }
        console2.log("wrote frontend/deployments.json");
    }

    function _seed(AquaWeightVault vault, address weth, address usdc, address deployer, uint256 initUsd)
        private
        returns (uint256 positionId)
    {
        uint256 mid = initUsd * 1e18;
        uint160 sqrtLo = _sqrtAt(mid / 2);
        uint160 sqrtHi = _sqrtAt(mid * 2);
        uint160 sqrtPrice = _sqrtAt(mid);
        uint128 liquidity = 10_000e6;
        uint256 need0 = LogCurveMath.getAmount0Delta(sqrtPrice, sqrtHi, liquidity, true);
        uint256 need1 = LogCurveMath.getAmount1Delta(sqrtLo, sqrtPrice, liquidity, true);
        need0 = need0 + need0 / 100 + 1;
        need1 = need1 + need1 / 100 + 1;
        IWETH9(weth).deposit{value: need0}();
        IERC20Mintable(weth).approve(address(vault), type(uint256).max);
        IERC20Mintable(usdc).approve(address(vault), type(uint256).max);
        require(IERC20Mintable(usdc).balanceOf(deployer) >= need1, "Need Sepolia USDC (faucet.circle.com)");
        (positionId,,) = vault.mint(
            weth, usdc, sqrtLo, sqrtHi, sqrtPrice, liquidity, 30, need0, need1, block.timestamp + 1 hours
        );
    }

    function _writeJson(
        ComputeAquaApp app,
        AquaWeightVault vault,
        WeightAuction auction,
        address aqua,
        address weth,
        address usdc,
        uint256 initUsd
    ) internal {
        string memory rpc = vm.envOr("RPC_PUBLIC_URL", string("https://ethereum-sepolia-rpc.publicnode.com"));
        string memory o = "deployments";
        vm.serializeUint(o, "chainId", block.chainid);
        vm.serializeString(o, "chainName", "Ethereum Sepolia (Aqua)");
        vm.serializeString(o, "rpc", rpc);
        vm.serializeString(o, "explorer", "https://sepolia.etherscan.io");
        vm.serializeUint(o, "startBlock", block.number);
        vm.serializeAddress(o, "aqua", aqua);
        vm.serializeAddress(o, "app", address(app));
        vm.serializeAddress(o, "vault", address(vault));
        vm.serializeAddress(o, "weights", address(vault.weights()));
        vm.serializeAddress(o, "weth", weth);
        vm.serializeAddress(o, "usdc", usdc);
        vm.serializeBool(o, "usdcMintable", false);
        vm.serializeBool(o, "wethMintable", false);
        vm.serializeUint(o, "defaultFeeBps", 30);
        vm.serializeUint(o, "initPrice", initUsd);
        string memory json = vm.serializeAddress(o, "auction", address(auction));
        vm.writeJson(json, "./frontend/deployments.json");
    }

    function _sqrtAt(uint256 humanPriceWad) private pure returns (uint160) {
        return uint160(FullMath.mulDiv(FixedPointMathLib.sqrt(humanPriceWad * 1e18), 1 << 96, 1e24));
    }
}
