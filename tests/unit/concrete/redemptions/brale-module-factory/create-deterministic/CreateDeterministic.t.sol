// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { BraleModuleFactoryBase } from "../BraleModuleFactoryBase.t.sol";
import { BraleModule } from "../../../../../../src/modules/redemptions/BraleModule.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";

contract CreateDeterministic_BraleModuleFactory_Test is BraleModuleFactoryBase {
    function test_RevertWhen_CallerIsNotFactoryOwner() external {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
    }

    function test_RevertWhen_StrangerFrontRunsTheSameParams() external {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);

        address module = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        assertEq(module, factory.predictDeterministicAddress(address(this), owner, paymentRails, DEFAULT_SALT));
    }

    function test_RevertWhen_OwnerIsZeroAddress() external {
        vm.expectRevert(Errors.BraleModuleFactory_ZeroOwner.selector);
        factory.createDeterministic(address(0), paymentRails, DEFAULT_SALT);
    }

    function test_RevertWhen_PaymentRailsIsZeroAddress() external {
        vm.expectRevert(Errors.BraleModuleFactory_ZeroPaymentRails.selector);
        factory.createDeterministic(owner, address(0), DEFAULT_SALT);
    }

    function test_RevertWhen_PaymentRailsHasNoCode() external {
        address eoa = makeAddr("notAContract");
        vm.expectRevert(abi.encodeWithSelector(Errors.BraleModuleFactory_PaymentRailsNotContract.selector, eoa));
        factory.createDeterministic(owner, eoa, DEFAULT_SALT);
    }

    function test_WhenParamsAreValid_ShouldDeployAndWire() external {
        address module = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        assertTrue(module.code.length > 0);
        assertEq(BraleModule(module).owner(), owner);
        assertEq(BraleModule(module).paymentRails(), paymentRails);
    }

    function test_WhenParamsAreValid_ShouldDeployToPredictedAddress() external {
        address predicted = factory.predictDeterministicAddress(address(this), owner, paymentRails, DEFAULT_SALT);
        address module = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        assertEq(module, predicted);
    }

    function test_WhenParamsAreValid_ShouldRegisterModule() external {
        address module = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        assertTrue(factory.isDeployedModule(module));
        assertEq(factory.getModuleCount(), 1);
        assertEq(factory.getModulesForPaymentRails(paymentRails).length, 1);
    }

    function test_WhenParamsAreValid_ShouldEmitEvent() external {
        address predicted = factory.predictDeterministicAddress(address(this), owner, paymentRails, DEFAULT_SALT);

        vm.expectEmit(true, true, true, true);
        emit BraleModuleCreated(predicted, paymentRails, owner);

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
        address module1 = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);
        address module2 = factory.createDeterministic(owner, otherPaymentRails, DEFAULT_SALT);
        assertTrue(module1 != module2);
    }

    function testFuzz_PredictedAddressMatchesActual(address fuzzOwner, bytes32 fuzzSalt) external {
        vm.assume(fuzzOwner != address(0));

        address predicted = factory.predictDeterministicAddress(address(this), fuzzOwner, paymentRails, fuzzSalt);
        address actual = factory.createDeterministic(fuzzOwner, paymentRails, fuzzSalt);
        assertEq(actual, predicted);
    }

    /// @dev The salt is bound to the caller, so each factory owner has a disjoint address space.
    function test_WhenSameSaltByNewFactoryOwner_ShouldNotCollide() external {
        address moduleA = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);

        address newFactoryOwner = makeAddr("newFactoryOwner");
        factory.transferOwnership(newFactoryOwner);
        vm.prank(newFactoryOwner);
        factory.acceptOwnership();

        vm.prank(newFactoryOwner);
        address moduleB = factory.createDeterministic(owner, paymentRails, DEFAULT_SALT);

        assertTrue(moduleA != moduleB);
        assertEq(moduleB, factory.predictDeterministicAddress(newFactoryOwner, owner, paymentRails, DEFAULT_SALT));
    }

    function test_PredictDeterministicAddress_IsPerDeployer() external view {
        address forThis = factory.predictDeterministicAddress(address(this), owner, paymentRails, DEFAULT_SALT);
        address forOther = factory.predictDeterministicAddress(foreignRailsOwner, owner, paymentRails, DEFAULT_SALT);
        assertTrue(forThis != forOther);
    }

    function test_PredictDeterministicAddress_IsIndependentOfMsgSender() external {
        address fromThis = factory.predictDeterministicAddress(address(this), owner, paymentRails, DEFAULT_SALT);
        vm.prank(stranger);
        address fromStranger = factory.predictDeterministicAddress(address(this), owner, paymentRails, DEFAULT_SALT);
        assertEq(fromThis, fromStranger);
    }
}
