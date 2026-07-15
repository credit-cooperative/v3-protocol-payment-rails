// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AtumModuleFactoryBase } from "../AtumModuleFactoryBase.t.sol";
import { AtumModule } from "../../../../../../../src/modules/contrib/bridges/AtumModule.sol";
import { Errors } from "../../../../../../../src/libraries/Errors.sol";

contract Create_AtumModuleFactory_Test is AtumModuleFactoryBase {
    function test_RevertWhen_OwnerIsZeroAddress() external {
        vm.expectRevert(Errors.AtumModuleFactory_ZeroOwner.selector);
        factory.create(address(0), paymentRails, keeper);
    }

    function test_RevertWhen_PaymentRailsIsZeroAddress() external {
        vm.expectRevert(Errors.AtumModuleFactory_ZeroPaymentRails.selector);
        factory.create(owner, address(0), keeper);
    }

    function test_RevertWhen_KeeperIsZeroAddress() external {
        vm.expectRevert(Errors.AtumModuleFactory_ZeroKeeper.selector);
        factory.create(owner, paymentRails, address(0));
    }

    function test_WhenParamsAreValid_ShouldDeployContract() external {
        address module = factory.create(owner, paymentRails, keeper);
        assertTrue(module.code.length > 0);
    }

    function test_WhenParamsAreValid_ShouldSetOwner() external {
        address module = factory.create(owner, paymentRails, keeper);
        assertEq(AtumModule(module).owner(), owner);
    }

    function test_WhenParamsAreValid_ShouldWirePaymentRails() external {
        address module = factory.create(owner, paymentRails, keeper);
        assertEq(AtumModule(module).paymentRails(), paymentRails);
    }

    function test_WhenParamsAreValid_ShouldSetKeeper() external {
        address module = factory.create(owner, paymentRails, keeper);
        assertEq(AtumModule(module).keeper(), keeper);
    }

    function test_WhenParamsAreValid_ShouldWirePermit2() external {
        address module = factory.create(owner, paymentRails, keeper);
        assertEq(AtumModule(module).permit2(), address(permit2));
    }

    function test_WhenParamsAreValid_ShouldRegisterModule() external {
        address module = factory.create(owner, paymentRails, keeper);
        assertTrue(factory.isDeployedModule(module));
    }

    function test_WhenParamsAreValid_ShouldIncrementModuleCount() external {
        assertEq(factory.getModuleCount(), 0);
        factory.create(owner, paymentRails, keeper);
        assertEq(factory.getModuleCount(), 1);
    }

    function test_WhenParamsAreValid_ShouldRegisterUnderPaymentRailsLookup() external {
        address module = factory.create(owner, paymentRails, keeper);

        address[] memory modules = factory.getModulesForPaymentRails(paymentRails);
        assertEq(modules.length, 1);
        assertEq(modules[0], module);
    }

    function test_WhenParamsAreValid_ShouldEmitEvent() external {
        // Check topic2 (paymentRails) and topic3 (owner) without asserting topic1 (unpredictable CREATE address).
        vm.expectEmit(false, true, true, true);
        emit AtumModuleCreated(address(0), paymentRails, owner);

        factory.create(owner, paymentRails, keeper);
    }

    function test_WhenCalledMultipleTimes_ShouldDeployDistinctInstances() external {
        address module1 = factory.create(owner, paymentRails, keeper);
        address module2 = factory.create(owner, paymentRails, keeper);
        assertTrue(module1 != module2);
    }

    function test_WhenCalledMultipleTimes_ShouldRegisterAllInstances() external {
        address module1 = factory.create(owner, paymentRails, keeper);
        address module2 = factory.create(owner, paymentRails, keeper);

        assertTrue(factory.isDeployedModule(module1));
        assertTrue(factory.isDeployedModule(module2));
        assertEq(factory.getModuleCount(), 2);

        address[] memory modules = factory.getDeployedModules();
        assertEq(modules.length, 2);
        assertEq(modules[0], module1);
        assertEq(modules[1], module2);
    }

    function test_WhenCalledMultipleTimes_ShouldAccumulateInPaymentRailsLookup() external {
        address module1 = factory.create(owner, paymentRails, keeper);
        address module2 = factory.create(owner, paymentRails, keeper);

        address[] memory modules = factory.getModulesForPaymentRails(paymentRails);
        assertEq(modules.length, 2);
        assertEq(modules[0], module1);
        assertEq(modules[1], module2);
    }
}
