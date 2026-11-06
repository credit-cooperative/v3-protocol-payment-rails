// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { BraleModuleFactory } from "../../../src/modules/redemptions/BraleModuleFactory.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployBraleModuleFactory
/// @author Credit Cooperative
/// @notice Deploys the BraleModuleFactory contract. Run once per chain; use the factory to deploy
///         a dedicated BraleModule per PaymentRails instance (e.g. per borrower).
///
///      `owner` is the only address allowed to call create()/createDeterministic(); pass the multi-sig.
///      The factory is not bound to a PaymentRailsFactory, so it does not need redeploying when
///      the rails factory is.
///
///      Usage:
///        source .env && \
///          forge script scripts/solidity/deploy/DeployBraleModuleFactory.s.sol \
///          --sig "run(address)" <FACTORY_OWNER> \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployBraleModuleFactory is BaseScript {
    function run(address _owner) public broadcast returns (BraleModuleFactory factory) {
        factory = new BraleModuleFactory(_owner);

        console2.log("=============================================================");
        console2.log("  DeployBraleModuleFactory - Complete");
        console2.log("=============================================================");
        console2.log("BraleModuleFactory:", address(factory));
        console2.log("Factory owner:     ", factory.owner());
        console2.log("");
        console2.log("Save to .env:");
        console2.log("  BRALE_MODULE_FACTORY_ADDRESS=%s", vm.toString(address(factory)));
        console2.log("");
        console2.log("Then deploy a module per PaymentRails, from the factory owner:");
        console2.log("  cast send $BRALE_MODULE_FACTORY_ADDRESS 'create(address,address)' \\");
        console2.log("    <MODULE_OWNER> <PAYMENT_RAILS>");
        console2.log("  Verify module.paymentRails() and module.owner(); follow src/modules/redemptions/README.md");
        console2.log("  onboarding before configureToken(token, \"BRALE_REDEMPTION\", module, minBalance,");
        console2.log("  encodeParams(depositAddress, usdc, minAmount), true).");
        console2.log("=============================================================");
    }
}
