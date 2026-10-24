// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { UnwrapModule } from "../../../src/modules/native/UnwrapModule.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployUnwrapModule
/// @author Credit Cooperative
/// @notice Deploys the UnwrapModule. Stateless — a single instance per chain can be shared across PaymentRails.
///         `wrappedNative` is the chain's canonical wrapped-native token (WETH, WAVAX).
///
///      Usage:
///        source .env && forge script scripts/solidity/deploy/DeployUnwrapModule.s.sol \
///          --sig "run(address)" <WRAPPED_NATIVE> \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployUnwrapModule is BaseScript {
    function run(address wrappedNative) public broadcast returns (UnwrapModule module) {
        module = new UnwrapModule(wrappedNative);

        console2.log("=============================================================");
        console2.log("  DeployUnwrapModule - Complete");
        console2.log("=============================================================");
        console2.log("UnwrapModule:     ", address(module));
        console2.log("Wrapped native: ", module.wrappedNative());
        console2.log("=============================================================");
    }
}
