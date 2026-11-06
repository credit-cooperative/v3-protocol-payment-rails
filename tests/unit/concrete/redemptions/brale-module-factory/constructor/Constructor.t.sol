// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { BraleModuleFactoryBase } from "../BraleModuleFactoryBase.t.sol";
import { BraleModuleFactory } from "../../../../../../src/modules/redemptions/BraleModuleFactory.sol";

contract Constructor_BraleModuleFactory_Test is BraleModuleFactoryBase {
    function test_RevertWhen_InitialOwnerIsZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new BraleModuleFactory(address(0));
    }

    function test_WhenInitialOwnerIsValid_ShouldSetOwner() external {
        BraleModuleFactory f = new BraleModuleFactory(owner);
        assertEq(f.owner(), owner);
    }

    function test_WhenInitialOwnerIsValid_RegistryIsEmpty() external {
        BraleModuleFactory f = new BraleModuleFactory(owner);
        assertEq(f.getModuleCount(), 0);
        assertEq(f.getDeployedModules().length, 0);
    }
}
