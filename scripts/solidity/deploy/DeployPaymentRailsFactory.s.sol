// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { PaymentRailsFactory } from "../../../src/core/PaymentRailsFactory.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployPaymentRailsFactory
/// @author Credit Cooperative
/// @notice Deploys the PaymentRailsFactory contract. Run once per chain; use the factory to deploy
///         PaymentRails instances.
///
///      `owner` is the only address allowed to call create()/createDeterministic(). It is taken as
///      an argument, so the deployer key never holds the role and needs no handover. Pass the
///      multi-sig unless an EOA is deliberately being given creation duty.
///
///      `wrappedNative` is the chain's wrapped-native token (WETH, WAVAX), baked into every instance the
///      factory creates. Pass `address(0)` to disable native ingress. Changing it later means a new factory.
///
///      Usage:
///        source .env && forge script scripts/solidity/deploy/DeployPaymentRailsFactory.s.sol \
///          --sig "run(address,address)" <FACTORY_OWNER> <WRAPPED_NATIVE> \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployPaymentRailsFactory is BaseScript {
    function run(address owner, address wrappedNative) public broadcast returns (PaymentRailsFactory factory) {
        factory = new PaymentRailsFactory(owner, wrappedNative);

        console2.log("=============================================================");
        console2.log("  DeployPaymentRailsFactory - Complete");
        console2.log("=============================================================");
        console2.log("PaymentRailsFactory:  ", address(factory));
        console2.log("Factory owner:        ", factory.owner());
        console2.log("Wrapped native:       ", factory.wrappedNative());
        if (wrappedNative != address(0)) {
            // Reverts on a non-token address: better here than at the first wrapNative().
            console2.log("Wrapped native symbol:", IERC20Metadata(wrappedNative).symbol());
        }
        console2.log("");
        console2.log("Save to .env:");
        console2.log("  PAYMENT_RAILS_FACTORY_ADDRESS=%s", vm.toString(address(factory)));
        console2.log("=============================================================");
    }
}
