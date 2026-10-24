// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { PaymentRails } from "../../../src/core/PaymentRails.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployPaymentRails
/// @author Credit Cooperative
/// @notice Deploys the PaymentRails contract. Run once per chain, then attach modules via configureToken().
///
///      `wrappedNative` is the chain's wrapped-native token (WETH, WAVAX); native value sent to the instance
///      is wrapped into it by `wrapNative()`. Pass `address(0)` to disable native ingress.
///
///      Usage:
///        source .env && forge script scripts/solidity/deploy/DeployPaymentRails.s.sol \
///          --sig "run(address,address)" <OWNER_ADDRESS> <WRAPPED_NATIVE> \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployPaymentRails is BaseScript {
    function run(address owner, address wrappedNative) public broadcast returns (PaymentRails paymentRails) {
        paymentRails = new PaymentRails(owner, wrappedNative);

        console2.log("=============================================================");
        console2.log("  DeployPaymentRails - Complete");
        console2.log("=============================================================");
        console2.log("Owner: ", owner);
        console2.log("Wrapped native:", wrappedNative);
        if (wrappedNative != address(0)) {
            // Reverts on a non-token address: better here than at the first wrapNative().
            console2.log("Wrapped native symbol:", IERC20Metadata(wrappedNative).symbol());
        }
        console2.log("PaymentRails:  ", address(paymentRails));
        console2.log("");
        console2.log("Save to .env:");
        console2.log("  PAYMENT_RAILS_ADDRESS=%s", vm.toString(address(paymentRails)));
        console2.log("=============================================================");
    }
}
