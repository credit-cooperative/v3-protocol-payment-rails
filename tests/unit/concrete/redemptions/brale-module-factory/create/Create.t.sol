// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { BraleModuleFactoryBase } from "../BraleModuleFactoryBase.t.sol";
import { BraleModule } from "../../../../../../src/modules/redemptions/BraleModule.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";

contract Create_BraleModuleFactory_Test is BraleModuleFactoryBase {
    function test_RevertWhen_CallerIsNotFactoryOwner() external {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.create(owner, paymentRails);
    }

    function test_RevertWhen_CallerIsPaymentRailsOwnerButNotFactoryOwner() external {
        vm.prank(foreignRailsOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, foreignRailsOwner));
        factory.create(owner, foreignPaymentRails);
    }

    function test_WhenUnauthorized_RegistryStaysEmpty() external {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.create(owner, foreignPaymentRails);

        assertEq(factory.getModuleCount(), 0);
        assertEq(factory.getModulesForPaymentRails(foreignPaymentRails).length, 0);
    }

    function test_RevertWhen_OwnerIsZeroAddress() external {
        vm.expectRevert(Errors.BraleModuleFactory_ZeroOwner.selector);
        factory.create(address(0), paymentRails);
    }

    function test_RevertWhen_PaymentRailsIsZeroAddress() external {
        vm.expectRevert(Errors.BraleModuleFactory_ZeroPaymentRails.selector);
        factory.create(owner, address(0));
    }

    function test_RevertWhen_PaymentRailsHasNoCode() external {
        address eoa = makeAddr("notAContract");
        vm.expectRevert(abi.encodeWithSelector(Errors.BraleModuleFactory_PaymentRailsNotContract.selector, eoa));
        factory.create(owner, eoa);
    }

    function test_WhenParamsAreValid_ShouldDeployContract() external {
        address module = factory.create(owner, paymentRails);
        assertTrue(module.code.length > 0);
    }

    function test_WhenParamsAreValid_ShouldSetOwner() external {
        address module = factory.create(owner, paymentRails);
        assertEq(BraleModule(module).owner(), owner);
    }

    function test_WhenCallerIsFactoryOwner_ShouldNotRequireOwningThePaymentRails() external {
        address module = factory.create(foreignRailsOwner, foreignPaymentRails);

        assertTrue(factory.isDeployedModule(module));
        assertEq(BraleModule(module).owner(), foreignRailsOwner);
        assertEq(BraleModule(module).paymentRails(), foreignPaymentRails);
        assertEq(factory.getModulesForPaymentRails(foreignPaymentRails).length, 1);
    }

    function test_WhenParamsAreValid_ShouldWirePaymentRails() external {
        address module = factory.create(owner, paymentRails);
        assertEq(BraleModule(module).paymentRails(), paymentRails);
        assertEq(BraleModule(module).redemptionNonce(), 0);
    }

    function test_WhenParamsAreValid_ShouldRegisterModule() external {
        address module = factory.create(owner, paymentRails);
        assertTrue(factory.isDeployedModule(module));
    }

    function test_WhenParamsAreValid_ShouldIncrementModuleCount() external {
        assertEq(factory.getModuleCount(), 0);
        factory.create(owner, paymentRails);
        assertEq(factory.getModuleCount(), 1);
    }

    function test_WhenParamsAreValid_ShouldRegisterUnderPaymentRailsLookup() external {
        address module = factory.create(owner, paymentRails);

        address[] memory modules = factory.getModulesForPaymentRails(paymentRails);
        assertEq(modules.length, 1);
        assertEq(modules[0], module);
    }

    function test_WhenParamsAreValid_ShouldEmitEvent() external {
        // Skip topic1 (unpredictable CREATE address); check paymentRails and owner.
        vm.expectEmit(false, true, true, true);
        emit BraleModuleCreated(address(0), paymentRails, owner);

        factory.create(owner, paymentRails);
    }

    function test_WhenCalledMultipleTimes_ShouldDeployDistinctInstances() external {
        address module1 = factory.create(owner, paymentRails);
        address module2 = factory.create(owner, paymentRails);
        assertTrue(module1 != module2);
    }

    function test_WhenCalledMultipleTimes_ShouldRegisterAllInstances() external {
        address module1 = factory.create(owner, paymentRails);
        address module2 = factory.create(owner, paymentRails);

        assertTrue(factory.isDeployedModule(module1));
        assertTrue(factory.isDeployedModule(module2));
        assertEq(factory.getModuleCount(), 2);

        address[] memory modules = factory.getDeployedModules();
        assertEq(modules[0], module1);
        assertEq(modules[1], module2);
    }

    function test_WhenCalledMultipleTimes_ShouldAccumulateInPaymentRailsLookup() external {
        address module1 = factory.create(owner, paymentRails);
        address module2 = factory.create(owner, paymentRails);

        address[] memory modules = factory.getModulesForPaymentRails(paymentRails);
        assertEq(modules.length, 2);
        assertEq(modules[0], module1);
        assertEq(modules[1], module2);
    }
}
