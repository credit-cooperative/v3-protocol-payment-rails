// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { ForwardModuleFactory } from "../../../src/modules/forwards/ForwardModuleFactory.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployForwardModuleFactory
/// @author Credit Cooperative
/// @notice Deploys the ForwardModuleFactory contract. Run once per chain; use the factory to deploy
///         ForwardModule instances so the registry attests that a module came from canonical bytecode.
///         ForwardModule is stateless, so a single module can be shared across PaymentRails instances.
///
///      Usage:
///        source .env && forge script scripts/solidity/deploy/DeployForwardModuleFactory.s.sol \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployForwardModuleFactory is BaseScript {
    function run() public broadcast returns (ForwardModuleFactory factory) {
        factory = new ForwardModuleFactory();

        console2.log("=============================================================");
        console2.log("  DeployForwardModuleFactory - Complete");
        console2.log("=============================================================");
        console2.log("ForwardModuleFactory:", address(factory));
        console2.log("");
        console2.log("Save to .env:");
        console2.log("  FORWARD_MODULE_FACTORY_ADDRESS=%s", vm.toString(address(factory)));
        console2.log("");
        console2.log("Then deploy a module (one shared instance is enough):");
        console2.log("  cast send $FORWARD_MODULE_FACTORY_ADDRESS 'create()'");
        console2.log("=============================================================");
    }
}
