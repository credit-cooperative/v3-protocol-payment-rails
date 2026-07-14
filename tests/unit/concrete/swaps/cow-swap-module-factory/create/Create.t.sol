// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { CowSwapModuleFactoryBase } from "../CowSwapModuleFactoryBase.t.sol";
import { CowSwapModule } from "../../../../../../src/modules/swaps/CowSwapModule.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";

contract Create_CowSwapModuleFactory_Test is CowSwapModuleFactoryBase {
    function test_RevertWhen_OwnerIsZeroAddress() external {
        vm.expectRevert(Errors.CowSwapModuleFactory_ZeroOwner.selector);
        factory.create(address(0), paymentRails);
    }

    function test_RevertWhen_PaymentRailsIsZeroAddress() external {
        vm.expectRevert(Errors.CowSwapModuleFactory_ZeroPaymentRails.selector);
        factory.create(owner, address(0));
    }

    function test_WhenParamsAreValid_ShouldDeployContract() external {
        address module = factory.create(owner, paymentRails);
        assertTrue(module.code.length > 0);
    }

    function test_WhenParamsAreValid_ShouldSetOwner() external {
        address module = factory.create(owner, paymentRails);
        assertEq(CowSwapModule(module).owner(), owner);
    }

    function test_WhenParamsAreValid_ShouldWirePaymentRails() external {
        address module = factory.create(owner, paymentRails);
        assertEq(CowSwapModule(module).paymentRails(), paymentRails);
    }

    function test_WhenParamsAreValid_ShouldWireChainConfig() external {
        address module = factory.create(owner, paymentRails);

        assertEq(CowSwapModule(module).cowSettlement(), address(cowSettlement));
        assertEq(CowSwapModule(module).cowDomainSeparator(), DOMAIN_SEPARATOR);
        assertEq(CowSwapModule(module).vaultRelayer(), vaultRelayer);
        assertEq(CowSwapModule(module).sequencerUptimeFeed(), factory.sequencerUptimeFeed());
        assertEq(CowSwapModule(module).sequencerGracePeriod(), factory.sequencerGracePeriod());
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
        // Check topic2 (paymentRails) and topic3 (owner) without asserting topic1 (unpredictable CREATE address).
        vm.expectEmit(false, true, true, true);
        emit CowSwapModuleCreated(address(0), paymentRails, owner);

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
        assertEq(modules.length, 2);
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
