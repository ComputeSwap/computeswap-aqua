// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IAqua} from "../src/aqua/IAqua.sol";
import {ComputeAquaApp} from "../src/aqua/ComputeAquaApp.sol";
import {AquaWeightVault} from "../src/aqua/AquaWeightVault.sol";
import {WeightAuction} from "../src/weights/WeightAuction.sol";

/// @notice Deploys only ComputeSwap contracts against an existing Aqua core. Aqua — © Degensoft Ltd 2025.
contract DeployAquaApp is Script {
    function run() external {
        address aquaAddress = vm.envAddress("AQUA_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        require(aquaAddress.code.length != 0, "Aqua core not deployed");
        require(treasury != address(0), "Treasury required");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        ComputeAquaApp app = new ComputeAquaApp(IAqua(aquaAddress));
        AquaWeightVault vault = new AquaWeightVault(app, 100);
        WeightAuction auction = new WeightAuction(vault.weights(), treasury);
        vm.stopBroadcast();
        console2.log("ComputeAquaApp", address(app));
        console2.log("AquaWeightVault", address(vault));
        console2.log("WeightToken", address(vault.weights()));
        console2.log("WeightAuction", address(auction));
    }
}
