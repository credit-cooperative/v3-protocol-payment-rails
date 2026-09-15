// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { CowSwapModuleFactoryBase } from "../CowSwapModuleFactoryBase.t.sol";
import { CowSwapModule } from "../../../../../../src/modules/swaps/CowSwapModule.sol";
import { PaymentRails } from "../../../../../../src/core/PaymentRails.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";

import { MockMalformedOwnerTarget, MockOwnerlessTarget } from "../../../../../shared/mocks/MockOwnerlessTarget.sol";

contract Create_CowSwapModuleFactory_Test is CowSwapModuleFactoryBase {
    function test_RevertWhen_OwnerIsZeroAddress() external {
        vm.prank(railsOwner);
        vm.expectRevert(Errors.CowSwapModuleFactory_ZeroOwner.selector);
        factory.create(address(0), paymentRails);
    }

    function test_RevertWhen_PaymentRailsIsZeroAddress() external {
        vm.prank(railsOwner);
        vm.expectRevert(Errors.CowSwapModuleFactory_ZeroPaymentRails.selector);
        factory.create(owner, address(0));
    }

    /*//////////////////////////////////////////////////////////////////////////
                            PAYMENT RAILS AUTHENTICATION
    //////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_PaymentRailsIsEOA() external {
        address eoa = makeAddr("eoaRails");
        vm.prank(eoa);
        vm.expectRevert(abi.encodeWithSelector(Errors.CowSwapModuleFactory_PaymentRailsNotContract.selector, eoa));
        factory.create(owner, eoa);
    }

    function test_RevertWhen_PaymentRailsDoesNotExposeOwner() external {
        address target = address(new MockOwnerlessTarget());
        vm.expectRevert(abi.encodeWithSelector(Errors.CowSwapModuleFactory_OwnerLookupFailed.selector, target));
        factory.create(owner, target);
    }

    function test_RevertWhen_PaymentRailsReturnsMalformedOwner() external {
        address target = address(new MockMalformedOwnerTarget());
        vm.expectRevert(abi.encodeWithSelector(Errors.CowSwapModuleFactory_OwnerLookupFailed.selector, target));
        factory.create(owner, target);
    }

    function test_RevertWhen_CallerIsNotPaymentRailsOwner() external {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CowSwapModuleFactory_CallerNotPaymentRailsOwner.selector, stranger, railsOwner
            )
        );
        factory.create(owner, paymentRails);
    }

    /// @dev The exact attack the authentication closes: an attacker calling create() with the victim's
    /// PaymentRails and an attacker-controlled module owner, so the victim's registry entry lists a
    /// factory-deployed, correctly-wired module that the attacker can cancel orders on.
    function test_RevertWhen_AttackerPlantsAttackerOwnedModuleUnderVictimRails() external {
        address attacker = makeAddr("attacker");

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CowSwapModuleFactory_CallerNotPaymentRailsOwner.selector, attacker, railsOwner
            )
        );
        factory.create(attacker, paymentRails);
    }

    function test_WhenAttackPrevented_VictimLookupStaysEmpty() external {
        address attacker = makeAddr("attacker");

        vm.prank(attacker);
        try factory.create(attacker, paymentRails) returns (address) {
            fail();
        } catch { }

        assertEq(factory.getModulesForPaymentRails(paymentRails).length, 0);
        assertEq(factory.getModuleCount(), 0);
    }

    function test_RevertWhen_CallerIsPendingOwnerOfInFlightTransfer() external {
        address newOwner = makeAddr("newOwner");

        vm.prank(railsOwner);
        PaymentRails(paymentRails).transferOwnership(newOwner);

        // Ownable2Step: ownership has not moved until accepted, so the pending owner is still a stranger.
        vm.prank(newOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CowSwapModuleFactory_CallerNotPaymentRailsOwner.selector, newOwner, railsOwner
            )
        );
        factory.create(owner, paymentRails);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CALLER IS THE PAYMENT RAILS OWNER
    //////////////////////////////////////////////////////////////////////////*/

    function test_WhenCallerIsRailsOwner_ShouldDeployContract() external {
        vm.prank(railsOwner);
        address module = factory.create(owner, paymentRails);
        assertTrue(module.code.length > 0);
    }

    function test_WhenCallerIsRailsOwner_ShouldSetOwner() external {
        vm.prank(railsOwner);
        address module = factory.create(owner, paymentRails);
        assertEq(CowSwapModule(module).owner(), owner);
    }

    /// @dev The PaymentRails owner authorizes the deployment but may hand the module to a different
    /// operator; authentication constrains who deploys, not who ends up owning the module.
    function test_WhenCallerIsRailsOwner_ShouldAllowDistinctModuleOwner() external {
        assertTrue(owner != railsOwner);

        vm.prank(railsOwner);
        address module = factory.create(owner, paymentRails);

        assertEq(CowSwapModule(module).owner(), owner);
        assertEq(PaymentRails(paymentRails).owner(), railsOwner);
    }

    function test_WhenCallerIsRailsOwner_ShouldWirePaymentRails() external {
        vm.prank(railsOwner);
        address module = factory.create(owner, paymentRails);
        assertEq(CowSwapModule(module).paymentRails(), paymentRails);
    }

    function test_WhenCallerIsRailsOwner_ShouldWireChainConfig() external {
        vm.prank(railsOwner);
        address module = factory.create(owner, paymentRails);

        assertEq(CowSwapModule(module).cowSettlement(), address(cowSettlement));
        assertEq(CowSwapModule(module).cowDomainSeparator(), DOMAIN_SEPARATOR);
        assertEq(CowSwapModule(module).vaultRelayer(), vaultRelayer);
        assertEq(CowSwapModule(module).sequencerUptimeFeed(), factory.sequencerUptimeFeed());
        assertEq(CowSwapModule(module).sequencerGracePeriod(), factory.sequencerGracePeriod());
    }

    function test_WhenCallerIsRailsOwner_ShouldRegisterModule() external {
        vm.prank(railsOwner);
        address module = factory.create(owner, paymentRails);
        assertTrue(factory.isDeployedModule(module));
    }

    function test_WhenCallerIsRailsOwner_ShouldIncrementModuleCount() external {
        assertEq(factory.getModuleCount(), 0);
        vm.prank(railsOwner);
        factory.create(owner, paymentRails);
        assertEq(factory.getModuleCount(), 1);
    }

    function test_WhenCallerIsRailsOwner_ShouldRegisterUnderPaymentRailsLookup() external {
        vm.prank(railsOwner);
        address module = factory.create(owner, paymentRails);

        address[] memory modules = factory.getModulesForPaymentRails(paymentRails);
        assertEq(modules.length, 1);
        assertEq(modules[0], module);
    }

    function test_WhenCallerIsRailsOwner_ShouldEmitEvent() external {
        // Check topic2 (paymentRails) and topic3 (owner) without asserting topic1 (unpredictable CREATE address).
        vm.expectEmit(false, true, true, true);
        emit CowSwapModuleCreated(address(0), paymentRails, owner);

        vm.prank(railsOwner);
        factory.create(owner, paymentRails);
    }

    function test_WhenCalledMultipleTimes_ShouldDeployDistinctInstances() external {
        vm.startPrank(railsOwner);
        address module1 = factory.create(owner, paymentRails);
        address module2 = factory.create(owner, paymentRails);
        vm.stopPrank();
        assertTrue(module1 != module2);
    }

    function test_WhenCalledMultipleTimes_ShouldRegisterAllInstances() external {
        vm.startPrank(railsOwner);
        address module1 = factory.create(owner, paymentRails);
        address module2 = factory.create(owner, paymentRails);
        vm.stopPrank();

        assertTrue(factory.isDeployedModule(module1));
        assertTrue(factory.isDeployedModule(module2));
        assertEq(factory.getModuleCount(), 2);

        address[] memory modules = factory.getDeployedModules();
        assertEq(modules.length, 2);
        assertEq(modules[0], module1);
        assertEq(modules[1], module2);
    }

    function test_WhenCalledMultipleTimes_ShouldAccumulateInPaymentRailsLookup() external {
        vm.startPrank(railsOwner);
        address module1 = factory.create(owner, paymentRails);
        address module2 = factory.create(owner, paymentRails);
        vm.stopPrank();

        address[] memory modules = factory.getModulesForPaymentRails(paymentRails);
        assertEq(modules.length, 2);
        assertEq(modules[0], module1);
        assertEq(modules[1], module2);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            OWNERSHIP TRANSFER FOLLOWS THE OWNER
    //////////////////////////////////////////////////////////////////////////*/

    function test_WhenOwnershipTransferred_ShouldRejectPreviousOwner() external {
        address newOwner = makeAddr("newOwner");

        vm.prank(railsOwner);
        PaymentRails(paymentRails).transferOwnership(newOwner);
        vm.prank(newOwner);
        PaymentRails(paymentRails).acceptOwnership();

        vm.prank(railsOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CowSwapModuleFactory_CallerNotPaymentRailsOwner.selector, railsOwner, newOwner
            )
        );
        factory.create(owner, paymentRails);
    }

    function test_WhenOwnershipTransferred_ShouldAcceptNewOwner() external {
        address newOwner = makeAddr("newOwner");

        vm.prank(railsOwner);
        PaymentRails(paymentRails).transferOwnership(newOwner);
        vm.prank(newOwner);
        PaymentRails(paymentRails).acceptOwnership();

        vm.prank(newOwner);
        address module = factory.create(owner, paymentRails);

        assertTrue(factory.isDeployedModule(module));
        assertEq(CowSwapModule(module).paymentRails(), paymentRails);
    }
}
