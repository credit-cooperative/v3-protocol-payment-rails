// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { CowSwapModuleFactoryBase } from "../CowSwapModuleFactoryBase.t.sol";
import { CowSwapModule } from "../../../../../../src/modules/swaps/CowSwapModule.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";

contract CreateDeterministic_CowSwapModuleFactory_Test is CowSwapModuleFactoryBase {
    function test_RevertWhen_OwnerIsZeroAddress() external {
        vm.expectRevert(Errors.CowSwapModuleFactory_ZeroOwner.selector);
        factory.createDeterministic(address(0), paymentRails, DEFAULT_SALT);
    }

    function test_RevertWhen_PaymentRailsIsZeroAddress() external {
        vm.expectRevert(Errors.CowSwapModuleFactory_ZeroPaymentRails.selector);
        factory.createDeterministic(owner, address(0), DEFAULT_SALT);
    }

    function test_WhenParamsAreValid_ShouldDeployContract() external {
        address module = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        assertTrue(module.code.length > 0);
    }

    function test_WhenParamsAreValid_ShouldSetOwner() external {
        address module = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        assertEq(CowSwapModule(module).owner(), owner);
    }

    function test_WhenParamsAreValid_ShouldWirePaymentRails() external {
        address module = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        assertEq(CowSwapModule(module).paymentRails(), paymentRails);
    }

    function test_WhenParamsAreValid_ShouldDeployToPredictedAddress() external {
        address predicted = factory.predictDeterministicAddress(owner, paymentRails, DEFAULT_SALT);
        address module = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        assertEq(module, predicted);
    }

    function test_WhenParamsAreValid_ShouldRegisterModule() external {
        address module = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        assertTrue(factory.isDeployedModule(module));
        assertEq(factory.getModuleCount(), 1);
    }

    function test_WhenParamsAreValid_ShouldEmitEvent() external {
        address predicted = factory.predictDeterministicAddress(owner, paymentRails, DEFAULT_SALT);

        vm.expectEmit(true, true, true, true);
        emit CowSwapModuleCreated(predicted, paymentRails, owner);

        factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
    }

    function test_RevertWhen_SameSaltReusedWithSameParams() external {
        factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        vm.expectRevert();
        factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
    }

    function test_WhenDifferentSaltsUsed_ShouldDeployToDifferentAddresses() external {
        address module1 = factory.createDeterministic(owner, paymentRails, bytes32(uint256(1)));
        address module2 = factory.createDeterministic(owner, paymentRails, bytes32(uint256(2)));
        assertTrue(module1 != module2);
    }

    function test_WhenSameSaltWithDifferentOwners_ShouldDeployToDifferentAddresses() external {
        address otherOwner = makeAddr("otherOwner");
        address module1 = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        address module2 = factory.createDeterministic(otherOwner, paymentRails, DEFAULT_SALT);
        assertTrue(module1 != module2);
    }

    function test_WhenSameSaltWithDifferentPaymentRails_ShouldDeployToDifferentAddresses() external {
        address otherPaymentRails = makeAddr("otherPaymentRails");
        address module1 = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        address module2 = factory.createDeterministic(owner, otherPaymentRails, DEFAULT_SALT);
        assertTrue(module1 != module2);
    }

    function testFuzz_PredictedAddressMatchesActual(
        address fuzzOwner,
        address fuzzPaymentRails,
        bytes32 fuzzSalt
    )
        external
    {
        vm.assume(fuzzOwner != address(0));
        vm.assume(fuzzPaymentRails != address(0));

        address predicted = factory.predictDeterministicAddress(fuzzOwner, fuzzPaymentRails, fuzzSalt);
        address actual = factory.createDeterministic(fuzzOwner, fuzzPaymentRails, fuzzSalt);
        assertEq(actual, predicted);
    }
}
