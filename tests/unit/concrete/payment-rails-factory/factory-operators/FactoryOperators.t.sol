// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { PaymentRailsFactoryBase } from "../PaymentRailsFactoryBase.t.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";

/// @notice Unit tests for PaymentRailsFactory factory operators.
/// @dev Tree: tests/unit/concrete/payment-rails-factory/factory-operators/factoryOperators.tree
contract PaymentRailsFactory_FactoryOperators_Test is PaymentRailsFactoryBase {
    function test_GivenNoOperatorApproved_ReportsFalseForAnyAddress() external view {
        assertFalse(factory.factoryOperators(operator), "operator");
        assertFalse(factory.factoryOperators(stranger), "stranger");
        assertFalse(factory.factoryOperators(address(this)), "owner");
    }

    function test_RevertWhen_CallerIsStranger() external {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.setFactoryOperator(operator, true);
    }

    function test_RevertWhen_CallerIsApprovedOperator() external {
        _approveOperator();

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        factory.setFactoryOperator(stranger, true);
    }

    function test_RevertWhen_OperatorIsZeroAddress() external {
        vm.expectRevert(Errors.PaymentRailsFactory_ZeroOperator.selector);
        factory.setFactoryOperator(address(0), true);
    }

    function test_WhenApproving_SetsTrueEmitsAndReturnsTrue() external {
        vm.expectEmit(true, true, true, true);
        emit FactoryOperatorSet(address(this), operator, true);

        bool result = factory.setFactoryOperator(operator, true);

        assertTrue(result, "return value");
        assertTrue(factory.factoryOperators(operator), "approved");
    }

    function test_WhenRevoking_SetsFalseAndEmits() external {
        _approveOperator();

        vm.expectEmit(true, true, true, true);
        emit FactoryOperatorSet(address(this), operator, false);

        factory.setFactoryOperator(operator, false);

        assertFalse(factory.factoryOperators(operator), "revoked");
    }

    function test_WhenValueUnchanged_DoesNotRevertAndEmitsAgain() external {
        _approveOperator();

        vm.expectEmit(true, true, true, true);
        emit FactoryOperatorSet(address(this), operator, true);

        factory.setFactoryOperator(operator, true);

        assertTrue(factory.factoryOperators(operator), "still approved");
    }

    function testFuzz_RevertWhen_CallerIsNotOwnerOrOperator(address caller) external {
        vm.assume(caller != address(this));
        vm.assume(!factory.factoryOperators(caller));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRailsFactory_NotOwnerOrOperator.selector, caller));
        factory.create(owner);
    }

    function testFuzz_RevertWhen_CallerIsNotOwnerOrOperator_CreateDeterministic(address caller) external {
        vm.assume(caller != address(this));
        vm.assume(!factory.factoryOperators(caller));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRailsFactory_NotOwnerOrOperator.selector, caller));
        factory.createDeterministic(owner, DEFAULT_SALT);
    }
}
