// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { PaymentRails } from "../../../../src/core/PaymentRails.sol";
import { BraleModule } from "../../../../src/modules/redemptions/BraleModule.sol";
import { MockERC20 } from "../../../shared/mocks/MockERC20.sol";

/// @title BraleModuleHandler
/// @notice Foundry invariant handler for BraleModule against the real PaymentRails.
/// @dev Actions never revert (fail_on_revert = true). Ghosts track successful redemptions.
contract BraleModuleHandler is Test {
    PaymentRails internal rails;
    BraleModule internal module;
    MockERC20 internal token;

    uint256 public ghost_successCount;
    uint256 public ghost_totalRedeemed;
    uint256 public ghost_lastNonce;

    constructor(PaymentRails _rails, BraleModule _module, MockERC20 _token) {
        rails = _rails;
        module = _module;
        token = _token;
    }

    /// @dev Mints `amount` to the rails and executes the action from a pseudo-random caller.
    function handler_execute(uint256 amount, uint256 callerSeed) external {
        amount = bound(amount, 1, 1e30);
        token.mint(address(rails), amount);

        address caller = address(uint160(bound(callerSeed, 1, type(uint160).max)));
        vm.prank(caller);
        bool ok = rails.executeAction(address(token), amount);
        if (ok) {
            ghost_lastNonce = module.redemptionNonce() - 1;
            ++ghost_successCount;
            ghost_totalRedeemed += amount;
        }
    }

    /// @dev Donations to the rails only change its balance; they must not affect module accounting.
    function handler_donateToRails(uint256 amount) external {
        amount = bound(amount, 1, 1e30);
        token.mint(address(rails), amount);
    }
}
