// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { NativeForwardModule } from "../../../src/modules/native/NativeForwardModule.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployNativeForwardModule
/// @author Credit Cooperative
/// @notice Deploys the NativeForwardModule. Stateless and chain-agnostic — a single instance can be shared
///         across PaymentRails. Pays a configured recipient in native value.
///
///      Usage:
///        source .env && forge script scripts/solidity/deploy/DeployNativeForwardModule.s.sol \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployNativeForwardModule is BaseScript {
    function run() public broadcast returns (NativeForwardModule module) {
        module = new NativeForwardModule();

        console2.log("=============================================================");
        console2.log("  DeployNativeForwardModule - Complete");
        console2.log("=============================================================");
        console2.log("NativeForwardModule: ", address(module));
        console2.log("=============================================================");
    }
}
