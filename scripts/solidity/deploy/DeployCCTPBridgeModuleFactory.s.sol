// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { CCTPBridgeModuleFactory } from "../../../src/modules/bridges/CCTPBridgeModuleFactory.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployCCTPBridgeModuleFactory
/// @author Credit Cooperative
/// @notice Deploys the CCTPBridgeModuleFactory contract. Run once per chain — Circle's TokenMessengerV2
///         and the native USDC address are fixed as factory immutables, so every module the factory
///         lists is guaranteed to burn the right token through the right messenger. CCTPBridgeModule is
///         stateless, so a single module can be shared across PaymentRails instances.
///
///      Usage:
///        source .env && forge script scripts/solidity/deploy/DeployCCTPBridgeModuleFactory.s.sol \
///          --sig "run(address,address)" <TOKEN_MESSENGER_V2> <USDC> \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployCCTPBridgeModuleFactory is BaseScript {
    function run(address _tokenMessenger, address _usdc) public broadcast returns (CCTPBridgeModuleFactory factory) {
        factory = new CCTPBridgeModuleFactory(_tokenMessenger, _usdc);

        console2.log("=============================================================");
        console2.log("  DeployCCTPBridgeModuleFactory - Complete");
        console2.log("=============================================================");
        console2.log("CCTPBridgeModuleFactory:", address(factory));
        console2.log("TokenMessengerV2:       ", _tokenMessenger);
        console2.log("USDC:                   ", _usdc);
        console2.log("");
        console2.log("Save to .env:");
        console2.log("  CCTP_BRIDGE_MODULE_FACTORY_ADDRESS=%s", vm.toString(address(factory)));
        console2.log("");
        console2.log("Then deploy a module (one shared instance is enough):");
        console2.log("  cast send $CCTP_BRIDGE_MODULE_FACTORY_ADDRESS 'create()'");
        console2.log("=============================================================");
    }
}
