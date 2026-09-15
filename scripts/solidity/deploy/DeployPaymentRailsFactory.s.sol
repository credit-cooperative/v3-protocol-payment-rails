// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { PaymentRailsFactory } from "../../../src/core/PaymentRailsFactory.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployPaymentRailsFactory
/// @author Credit Cooperative
/// @notice Deploys the PaymentRailsFactory contract. Run once per chain; use the factory to deploy
///         PaymentRails instances.
///
///      Usage:
///        source .env && forge script scripts/solidity/deploy/DeployPaymentRailsFactory.s.sol \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployPaymentRailsFactory is BaseScript {
    function run() public broadcast returns (PaymentRailsFactory factory) {
        factory = new PaymentRailsFactory();

        console2.log("=============================================================");
        console2.log("  DeployPaymentRailsFactory - Complete");
        console2.log("=============================================================");
        console2.log("PaymentRailsFactory:  ", address(factory));
        console2.log("");
        console2.log("Save to .env:");
        console2.log("  PAYMENT_RAILS_FACTORY_ADDRESS=%s", vm.toString(address(factory)));
        console2.log("=============================================================");
    }
}
