// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Aqua} from "aqua/src/Aqua.sol";
import {IAqua} from "../src/aqua/IAqua.sol";
import {ComputeAquaApp} from "../src/aqua/ComputeAquaApp.sol";
import {AquaWeightVault} from "../src/aqua/AquaWeightVault.sol";
import {WeightAuction} from "../src/weights/WeightAuction.sol";

contract DeployAquaLocal is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);
        Aqua aqua = new Aqua();
        ComputeAquaApp app = new ComputeAquaApp(IAqua(address(aqua)));
        AquaWeightVault vault = new AquaWeightVault(app, 100);
        WeightAuction auction = new WeightAuction(vault.weights(), deployer);
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH", 18);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        weth.mint(deployer, 1_000 ether);
        usdc.mint(deployer, 1_000e6);
        weth.approve(address(vault), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        (uint256 positionId,,) = vault.mint(
            address(weth),
            address(usdc),
            _sqrtAt(0.5e18),
            _sqrtAt(2e18),
            _sqrtAt(1e18),
            100e6,
            30,
            type(uint256).max,
            type(uint256).max,
            block.timestamp + 1 hours
        );
        vm.stopBroadcast();
        _writeJson(
            address(aqua),
            address(app),
            address(vault),
            address(vault.weights()),
            address(auction),
            address(weth),
            address(usdc),
            block.number
        );
        console2.log("Aqua core", address(aqua));
        console2.log("ComputeAquaApp", address(app));
        console2.log("AquaWeightVault", address(vault));
        console2.log("WeightToken", address(vault.weights()));
        console2.log("WeightAuction", address(auction));
        console2.log("WETH", address(weth));
        console2.log("USDC", address(usdc));
        console2.log("Initial position ID", positionId);
        console2.log("wrote frontend/deployments.json");
    }

    function _writeJson(
        address aqua,
        address app,
        address vault,
        address weights,
        address auction,
        address weth,
        address usdc,
        uint256 startBlock
    ) internal {
        string memory o = "deployments";
        vm.serializeUint(o, "chainId", block.chainid);
        vm.serializeString(o, "chainName", "Local Aqua");
        vm.serializeString(o, "rpc", "http://127.0.0.1:8546");
        vm.serializeUint(o, "startBlock", startBlock);
        vm.serializeAddress(o, "aqua", aqua);
        vm.serializeAddress(o, "app", app);
        vm.serializeAddress(o, "vault", vault);
        vm.serializeAddress(o, "weights", weights);
        vm.serializeAddress(o, "weth", weth);
        vm.serializeAddress(o, "usdc", usdc);
        vm.serializeBool(o, "usdcMintable", true);
        vm.serializeBool(o, "wethMintable", true);
        vm.serializeUint(o, "defaultFeeBps", 30);
        vm.serializeUint(o, "initPrice", 1);
        string memory json = vm.serializeAddress(o, "auction", auction);
        vm.writeJson(json, "./frontend/deployments.json");
    }

    function _sqrtAt(uint256 humanPriceWad) private pure returns (uint160) {
        return uint160(FullMath.mulDiv(FixedPointMathLib.sqrt(humanPriceWad * 1e18), 1 << 96, 1e24));
    }
}
