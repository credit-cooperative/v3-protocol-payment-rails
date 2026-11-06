// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BraleModuleBase } from "../BraleModuleBase.t.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";

contract BraleModule_RenounceOwnership_Test is BraleModuleBase {
    function test_RevertWhen_CalledByOwner() external {
        vm.expectRevert(Errors.BraleModule_OwnershipCannotBeRenounced.selector);
        vm.prank(owner);
        module.renounceOwnership();
    }

    function test_RevertWhen_CalledByNonOwner() external {
        vm.expectRevert(Errors.BraleModule_OwnershipCannotBeRenounced.selector);
        vm.prank(attacker);
        module.renounceOwnership();
    }

    function test_WhenRenounceFails_TwoStepTransferStillWorks() external {
        vm.prank(owner);
        vm.expectRevert(Errors.BraleModule_OwnershipCannotBeRenounced.selector);
        module.renounceOwnership();

        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        module.transferOwnership(newOwner);
        assertEq(module.owner(), owner);

        vm.prank(newOwner);
        module.acceptOwnership();
        assertEq(module.owner(), newOwner);
    }
}
