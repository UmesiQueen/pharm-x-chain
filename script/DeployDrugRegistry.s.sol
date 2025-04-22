// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {DrugRegistry} from "../src/DrugRegistry.sol";

contract DeployDrugRegistry is Script {
    function deployDrugRegistry(address mostRecentGlobalRegistry) public {
        vm.startBroadcast();
        DrugRegistry drugRegistry = new DrugRegistry(mostRecentGlobalRegistry);

        console2.log("DrugRegistry deployed at address:", address(drugRegistry));

        vm.stopBroadcast();
    }

    function run() external {
        // Get most recent GlobalRegistry deployment address
        address mostRecentGlobalRegistry = DevOpsTools.get_most_recent_deployment("GlobalRegistry", block.chainid);
        console2.log("Most recent GlobalRegistry address:", mostRecentGlobalRegistry);

        // Deploy DrugRegistry with the most recent GlobalRegistry address
        deployDrugRegistry(mostRecentGlobalRegistry);
    }
}
