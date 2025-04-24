// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {SupplyChainRegistry} from "../src/SupplyChainRegistry.sol";

contract DeploySupplyChainRegistry is Script {
    function deploySupplyChainRegistry(address mostRecentGlobalRegistry, address mostRecentDrugRegistry) public {
        vm.startBroadcast();
        SupplyChainRegistry supplyChainRegistry =
            new SupplyChainRegistry(mostRecentGlobalRegistry, mostRecentDrugRegistry);

        console2.log("SupplyChainRegistry deployed at address:", address(supplyChainRegistry));

        vm.stopBroadcast();
    }

    function run() external {
        // Get most recent GlobalRegistry deployment address
        address mostRecentGlobalRegistry = DevOpsTools.get_most_recent_deployment("GlobalRegistry", block.chainid);
        address mostRecentDrugRegistry = DevOpsTools.get_most_recent_deployment("DrugRegistry", block.chainid);
        console2.log("Most recent GlobalRegistry address:", mostRecentGlobalRegistry);
        console2.log("Most recent DrugRegistry address:", mostRecentDrugRegistry);

        deploySupplyChainRegistry(mostRecentGlobalRegistry, mostRecentDrugRegistry);
    }
}
