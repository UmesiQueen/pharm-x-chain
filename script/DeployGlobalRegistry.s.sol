// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {GlobalRegistry, IGlobalRegistry} from "src/GlobalRegistry.sol";

contract DeployGlobalRegistryScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy the GlobalRegistry contract
        GlobalRegistry globalRegistry = new GlobalRegistry();

        // Log the deployment
        console2.log("GlobalRegistry deployed at address:", address(globalRegistry));

        // Display contract information
        address owner = globalRegistry.owner();
        console2.log("Contract owner:", owner);

        // Get owner details (automatically registered as regulator)
        (
            string memory name,
            string memory location,
            string memory licenseNumber,
            IGlobalRegistry.Role role,
            bool isActive,
            uint256 registrationDate
        ) = globalRegistry.getEntityDetails(owner);

        console2.log("\nDeployer registered as:");
        console2.log("- Name:", name);
        console2.log("- Role: REGULATOR (", uint256(role), ")");
        console2.log("- License:", licenseNumber);
        console2.log("- Location:", location);
        console2.log("- Active:", isActive);
        console2.log("- Registration Date:", registrationDate);

        vm.stopBroadcast();
    }
}
