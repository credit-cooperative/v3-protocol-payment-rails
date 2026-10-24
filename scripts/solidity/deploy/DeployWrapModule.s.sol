// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { WrapModule } from "../../../src/modules/native/WrapModule.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployWrapModule
/// @author Credit Cooperative
/// @notice Deploys the WrapModule. Stateless — a single instance per chain can be shared across PaymentRails.
///         `wrappedNative` is the chain's canonical wrapped-native token (WETH, WAVAX).
///
///      Usage:
///        source .env && forge script scripts/solidity/deploy/DeployWrapModule.s.sol \
///          --sig "run(address)" <WRAPPED_NATIVE> \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployWrapModule is BaseScript {
    function run(address wrappedNative) public broadcast returns (WrapModule module) {
        module = new WrapModule(wrappedNative);

        console2.log("=============================================================");
        console2.log("  DeployWrapModule - Complete");
        console2.log("=============================================================");
        console2.log("WrapModule:     ", address(module));
        console2.log("Wrapped native: ", module.wrappedNative());
        console2.log("=============================================================");
    }
}
