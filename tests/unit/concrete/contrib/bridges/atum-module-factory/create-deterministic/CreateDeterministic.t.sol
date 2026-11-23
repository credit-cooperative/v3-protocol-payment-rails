// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AtumModuleFactoryBase } from "../AtumModuleFactoryBase.t.sol";
import { AtumModule } from "../../../../../../../src/modules/contrib/bridges/AtumModule.sol";
import { Errors } from "../../../../../../../src/libraries/Errors.sol";
import { PaymentRails } from "../../../../../../../src/core/PaymentRails.sol";

contract CreateDeterministic_AtumModuleFactory_Test is AtumModuleFactoryBase {
    function test_RevertWhen_OwnerIsZeroAddress() external {
        vm.expectRevert(Errors.AtumModuleFactory_ZeroOwner.selector);
        factory.createDeterministic(address(0), paymentRails, keeper, DEFAULT_SALT);
    }

    function test_RevertWhen_PaymentRailsIsZeroAddress() external {
        vm.expectRevert(Errors.AtumModuleFactory_ZeroPaymentRails.selector);
        factory.createDeterministic(owner, address(0), keeper, DEFAULT_SALT);
    }

    function test_RevertWhen_KeeperIsZeroAddress() external {
        vm.expectRevert(Errors.AtumModuleFactory_ZeroKeeper.selector);
        factory.createDeterministic(owner, paymentRails, address(0), DEFAULT_SALT);
    }

    function test_WhenParamsAreValid_ShouldDeployContract() external {
        address module = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
        assertTrue(module.code.length > 0);
    }

    function test_WhenParamsAreValid_ShouldSetOwner() external {
        address module = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
        assertEq(AtumModule(module).owner(), owner);
    }

    function test_WhenParamsAreValid_ShouldWirePaymentRails() external {
        address module = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
        assertEq(AtumModule(module).paymentRails(), paymentRails);
    }

    function test_WhenParamsAreValid_ShouldSetKeeper() external {
        address module = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
        assertEq(AtumModule(module).keeper(), keeper);
    }

    /// Mirror of the `create()` test: the deterministic path is not bound to a PaymentRailsFactory
    /// either, so a PaymentRails deployed anywhere is accepted.
    function test_CreateDeterministic_AcceptsPaymentRailsDeployedOutsideThePaymentRailsFactory() external {
        address direct = address(new PaymentRails(address(this)));
        address module = factory.createDeterministic(owner, direct, keeper, DEFAULT_SALT);

        assertTrue(factory.isDeployedModule(module));
        assertEq(AtumModule(module).paymentRails(), direct);
        assertEq(module, factory.predictDeterministicAddress(address(this), owner, direct, keeper, DEFAULT_SALT));
    }

    function test_WhenParamsAreValid_ShouldDeployToPredictedAddress() external {
        address predicted =
            factory.predictDeterministicAddress(address(this), owner, paymentRails, keeper, DEFAULT_SALT);
        address module = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
        assertEq(module, predicted);
    }

    function test_WhenParamsAreValid_ShouldRegisterModule() external {
        address module = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
        assertTrue(factory.isDeployedModule(module));
        assertEq(factory.getModuleCount(), 1);
    }

    function test_WhenParamsAreValid_ShouldEmitEvent() external {
        address predicted =
            factory.predictDeterministicAddress(address(this), owner, paymentRails, keeper, DEFAULT_SALT);

        vm.expectEmit(true, true, true, true);
        emit AtumModuleCreated(predicted, paymentRails, owner, keeper);

        factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
    }

    function test_RevertWhen_SameSaltReusedWithSameParams() external {
        factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
        vm.expectRevert();
        factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
    }

    function test_WhenDifferentSaltsUsed_ShouldDeployToDifferentAddresses() external {
        address module1 = factory.createDeterministic(owner, paymentRails, keeper, bytes32(uint256(1)));
        address module2 = factory.createDeterministic(owner, paymentRails, keeper, bytes32(uint256(2)));
        assertTrue(module1 != module2);
    }

    function test_WhenSameSaltWithDifferentOwners_ShouldDeployToDifferentAddresses() external {
        address otherOwner = makeAddr("otherOwner");
        address module1 = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
        address module2 = factory.createDeterministic(otherOwner, paymentRails, keeper, DEFAULT_SALT);
        assertTrue(module1 != module2);
    }

    function test_WhenSameSaltWithDifferentPaymentRails_ShouldDeployToDifferentAddresses() external {
        address module1 = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
        address module2 = factory.createDeterministic(owner, otherPaymentRails, keeper, DEFAULT_SALT);
        assertTrue(module1 != module2);
    }

    /// @dev The PaymentRails address is not fuzzed: it must have code, so an arbitrary address
    ///      cannot be used. Owner, keeper and salt stay fuzzed, which is what this test is actually
    ///      about -- that prediction tracks deployment across inputs.
    function testFuzz_PredictedAddressMatchesActual(address fuzzOwner, address fuzzKeeper, bytes32 fuzzSalt) external {
        vm.assume(fuzzOwner != address(0));
        vm.assume(fuzzKeeper != address(0));

        address predicted =
            factory.predictDeterministicAddress(address(this), fuzzOwner, paymentRails, fuzzKeeper, fuzzSalt);
        address actual = factory.createDeterministic(fuzzOwner, paymentRails, fuzzKeeper, fuzzSalt);
        assertEq(actual, predicted);
    }

    /// I-04. The salt is bound to the caller. With creation restricted to the owner and approved
    /// operators no third party can front-run, but the binding still keeps each factory owner's
    /// address space disjoint: after an ownership transfer, the new owner reusing a salt with the
    /// same params does not collide with the old owner's deployment.
    function test_CreateDeterministic_SameSaltDifferentDeployersDoNotCollide() external {
        address moduleA = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);

        address newFactoryOwner = makeAddr("newFactoryOwner");
        factory.transferOwnership(newFactoryOwner);
        vm.prank(newFactoryOwner);
        factory.acceptOwnership();

        vm.prank(newFactoryOwner);
        address moduleB = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);

        assertTrue(moduleA != moduleB, "same salt must not mean the same address for two deployers");
        assertEq(
            moduleB, factory.predictDeterministicAddress(newFactoryOwner, owner, paymentRails, keeper, DEFAULT_SALT)
        );
    }

    /// I-04 with operators. The operator's address space is its own: the prediction for the
    /// operator matches the deployment it submits, and the owner's prediction does not.
    function test_WhenCallerIsApprovedOperator_DeploysAtOperatorScopedAddress() external {
        _approveOperator();

        address predictedForOperator =
            factory.predictDeterministicAddress(operator, owner, paymentRails, keeper, DEFAULT_SALT);
        address predictedForOwner =
            factory.predictDeterministicAddress(address(this), owner, paymentRails, keeper, DEFAULT_SALT);

        vm.prank(operator);
        address module = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);

        assertEq(module, predictedForOperator, "operator-scoped prediction");
        assertTrue(module != predictedForOwner, "owner prediction must not match");
        assertTrue(factory.isDeployedModule(module));
    }

    /// I-04 with operators. The owner and an operator can use the same salt and params without
    /// colliding, in either order.
    function test_CreateDeterministic_OwnerAndOperatorSameSaltDoNotCollide() external {
        _approveOperator();

        address ownerModule = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);

        vm.prank(operator);
        address operatorModule = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);

        assertTrue(ownerModule != operatorModule, "same salt must not mean the same address");
        assertEq(
            ownerModule, factory.predictDeterministicAddress(address(this), owner, paymentRails, keeper, DEFAULT_SALT)
        );
        assertEq(
            operatorModule, factory.predictDeterministicAddress(operator, owner, paymentRails, keeper, DEFAULT_SALT)
        );
        assertEq(factory.getModuleCount(), 2);
    }

    function test_RevertWhen_CallerIsRevokedOperator() external {
        _approveOperator();
        factory.setFactoryOperator(operator, false);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Errors.AtumModuleFactory_NotOwnerOrOperator.selector, operator));
        factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
    }

    /// The salt is bound to the caller, so prediction for a different deployer differs.
    function test_PredictDeterministicAddress_IsPerDeployer() external view {
        address forThis = factory.predictDeterministicAddress(address(this), owner, paymentRails, keeper, DEFAULT_SALT);
        address forOther =
            factory.predictDeterministicAddress(foreignRailsOwner, owner, paymentRails, keeper, DEFAULT_SALT);
        assertTrue(forThis != forOther, "prediction must be deployer-scoped");
    }

    /// L-01. Both creation paths are gated: leaving either open would defeat the restriction.
    /// An approved operator extends the trusted set but does not open creation.
    function test_RevertWhen_CallerIsNotOwnerOrOperator() external {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Errors.AtumModuleFactory_NotOwnerOrOperator.selector, stranger));
        factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
    }

    function test_RevertWhen_CallerIsPaymentRailsOwnerButNotOwnerOrOperator() external {
        vm.prank(foreignRailsOwner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AtumModuleFactory_NotOwnerOrOperator.selector, foreignRailsOwner));
        factory.createDeterministic(owner, foreignPaymentRails, keeper, DEFAULT_SALT);
    }

    /// Restricting creation to owner/operators is also what stops a mempool observer occupying the address first.
    function test_RevertWhen_StrangerFrontRunsTheSameParams() external {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Errors.AtumModuleFactory_NotOwnerOrOperator.selector, stranger));
        factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);

        address module = factory.createDeterministic(owner, paymentRails, keeper, DEFAULT_SALT);
        assertEq(module, factory.predictDeterministicAddress(address(this), owner, paymentRails, keeper, DEFAULT_SALT));
    }
}
