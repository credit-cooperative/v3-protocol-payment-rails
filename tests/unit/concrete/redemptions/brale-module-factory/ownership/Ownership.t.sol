// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { BraleModuleFactoryBase } from "../BraleModuleFactoryBase.t.sol";
import { BraleModuleFactory } from "../../../../../../src/modules/redemptions/BraleModuleFactory.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";

contract Ownership_BraleModuleFactory_Test is BraleModuleFactoryBase {
    function test_RevertWhen_RenounceOwnershipCalled() external {
        vm.expectRevert(Errors.BraleModuleFactory_OwnershipCannotBeRenounced.selector);
        factory.renounceOwnership();
    }

    function test_WhenDeployed_DeployerIsNotOwner() external {
        BraleModuleFactory f = new BraleModuleFactory(owner);
        assertNotEq(f.owner(), address(this));
    }

    function test_WhenOwnershipTransferred_RequiresAcceptance() external {
        factory.transferOwnership(owner);
        assertEq(factory.owner(), address(this));
        assertEq(factory.pendingOwner(), owner);

        vm.prank(owner);
        factory.acceptOwnership();
        assertEq(factory.owner(), owner);
        assertEq(factory.pendingOwner(), address(0));
    }

    function test_WhenOwnershipTransferred_NewOwnerCanCreate() external {
        factory.transferOwnership(owner);
        vm.prank(owner);
        factory.acceptOwnership();

        vm.prank(owner);
        address module = factory.create(owner, paymentRails);
        assertTrue(factory.isDeployedModule(module));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.create(owner, paymentRails);
    }

    function test_WhenOwnershipTransferred_PreviousOwnerCannotCreate() external {
        factory.transferOwnership(owner);
        vm.prank(owner);
        factory.acceptOwnership();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        factory.create(owner, paymentRails);
    }
}
