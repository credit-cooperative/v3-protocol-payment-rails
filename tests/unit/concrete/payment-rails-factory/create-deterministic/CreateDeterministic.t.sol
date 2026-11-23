// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsFactoryBase } from "../PaymentRailsFactoryBase.t.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";

contract CreateDeterministic_Test is PaymentRailsFactoryBase {
    function test_RevertWhen_CallerIsNotOwnerOrOperator() external {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRailsFactory_NotOwnerOrOperator.selector, stranger));
        factory.createDeterministic(owner, DEFAULT_SALT);
    }

    /// @dev The prediction does not depend on the caller, so an operator deploys to the same address
    /// the owner would.
    function test_WhenCallerIsApprovedOperator_ShouldDeployAtPredictedAddress() external {
        _approveOperator();
        address predicted = factory.predictDeterministicAddress(owner, DEFAULT_SALT);

        vm.prank(operator);
        address instance = factory.createDeterministic(owner, DEFAULT_SALT);

        assertEq(instance, predicted);
        assertTrue(factory.isDeployedInstance(instance));
    }

    function test_RevertWhen_CallerIsRevokedOperator() external {
        _approveOperator();
        factory.setFactoryOperator(operator, false);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRailsFactory_NotOwnerOrOperator.selector, operator));
        factory.createDeterministic(owner, DEFAULT_SALT);
    }

    function test_RevertWhen_OwnerIsZeroAddress() external {
        vm.expectRevert(Errors.PaymentRailsFactory_ZeroOwner.selector);
        factory.createDeterministic(address(0), DEFAULT_SALT);
    }

    function test_WhenOwnerIsValid_ShouldDeployContract() external {
        address instance = factory.createDeterministic(owner, DEFAULT_SALT);
        assertTrue(instance.code.length > 0);
    }

    function test_WhenOwnerIsValid_ShouldSetOwner() external {
        address instance = factory.createDeterministic(owner, DEFAULT_SALT);
        assertEq(PaymentRails(payable(instance)).owner(), owner);
    }

    function test_WhenOwnerIsValid_ShouldDeployToPredictedAddress() external {
        address predicted = factory.predictDeterministicAddress(owner, DEFAULT_SALT);
        address instance = factory.createDeterministic(owner, DEFAULT_SALT);
        assertEq(instance, predicted);
    }

    function test_WhenOwnerIsValid_ShouldRegisterInstance() external {
        address instance = factory.createDeterministic(owner, DEFAULT_SALT);
        assertTrue(factory.isDeployedInstance(instance));
        assertEq(factory.getInstanceCount(), 1);
    }

    function test_WhenOwnerIsValid_ShouldEmitEvent() external {
        address predicted = factory.predictDeterministicAddress(owner, DEFAULT_SALT);

        vm.expectEmit(true, true, false, true);
        emit PaymentRailsCreated(predicted, owner);

        factory.createDeterministic(owner, DEFAULT_SALT);
    }

    function test_RevertWhen_SameSaltReusedWithSameOwner() external {
        factory.createDeterministic(owner, DEFAULT_SALT);
        vm.expectRevert();
        factory.createDeterministic(owner, DEFAULT_SALT);
    }

    function test_WhenDifferentSaltsUsed_ShouldDeployToDifferentAddresses() external {
        address instance1 = factory.createDeterministic(owner, bytes32(uint256(1)));
        address instance2 = factory.createDeterministic(owner, bytes32(uint256(2)));
        assertTrue(instance1 != instance2);
    }

    function test_WhenSameSaltWithDifferentOwners_ShouldDeployToDifferentAddresses() external {
        address otherOwner = makeAddr("otherOwner");
        address instance1 = factory.createDeterministic(owner, DEFAULT_SALT);
        address instance2 = factory.createDeterministic(otherOwner, DEFAULT_SALT);
        assertTrue(instance1 != instance2);
    }

    function testFuzz_PredictedAddressMatchesActual(address fuzzOwner, bytes32 fuzzSalt) external {
        vm.assume(fuzzOwner != address(0));

        address predicted = factory.predictDeterministicAddress(fuzzOwner, fuzzSalt);
        address actual = factory.createDeterministic(fuzzOwner, fuzzSalt);
        assertEq(actual, predicted);
    }

    /// @dev The salt is not caller-bound: once an operator deploys, the owner's identical call
    /// reverts, but the contract sits at the address both would have used (griefing only).
    function test_RevertWhen_OperatorDeployedSameArgsAndSaltFirst() external {
        _approveOperator();
        address predicted = factory.predictDeterministicAddress(owner, DEFAULT_SALT);

        vm.prank(operator);
        address instance = factory.createDeterministic(owner, DEFAULT_SALT);
        assertEq(instance, predicted);

        vm.expectRevert();
        factory.createDeterministic(owner, DEFAULT_SALT);

        assertTrue(factory.isDeployedInstance(predicted));
        assertEq(factory.getInstanceCount(), 1);
    }
}
