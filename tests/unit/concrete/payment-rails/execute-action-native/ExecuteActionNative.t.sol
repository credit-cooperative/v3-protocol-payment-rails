// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";

contract PaymentRailsExecuteActionNativeTest is PaymentRailsBase {
    uint256 internal constant VALUE = 3 ether;

    function test_RevertWhen_TheNativeKeyIsNotConfigured() external {
        _sendNative(executor, VALUE);

        vm.expectRevert(Errors.PaymentRails_TokenNotEnabled.selector);
        paymentRails.executeAction(NATIVE, VALUE);
    }

    function test_RevertWhen_AmountIsZero() external givenNativeConfigured {
        _sendNative(executor, VALUE);

        vm.expectRevert(Errors.PaymentRails_ZeroAmount.selector);
        paymentRails.executeAction(NATIVE, 0);
    }

    function test_RevertWhen_AmountIsBelowMinBalance() external givenNativeConfigured {
        _sendNative(executor, VALUE);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.PaymentRails_BelowMinimumBalance.selector, NATIVE_MIN - 1, NATIVE_MIN)
        );
        paymentRails.executeAction(NATIVE, NATIVE_MIN - 1);
    }

    function test_RevertWhen_NativeBalanceIsInsufficient() external givenNativeConfigured {
        _sendNative(executor, VALUE);

        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRails_InsufficientBalance.selector, VALUE, VALUE + 1));
        paymentRails.executeAction(NATIVE, VALUE + 1);
    }

    function test_WhenTheModuleSucceeds() external givenNativeConfigured {
        _sendNative(executor, VALUE);
        uint256 push = 1 ether;

        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit ActionExecuted(NATIVE, NATIVE_ACTION_TYPE, push, push, NATIVE, executor);

        vm.prank(executor);
        bool success = paymentRails.executeAction(NATIVE, push);

        assertTrue(success, "success");
        assertEq(address(nativeModule).balance, push, "module must hold exactly the pushed value");
        assertEq(nativeModule.lastAmount(), push, "amount passed to the module");
        assertEq(address(paymentRails).balance, VALUE - push, "remaining native");
    }

    function test_WhenTheModuleReverts() external givenNativeConfigured {
        _sendNative(executor, VALUE);
        nativeModule.setExecuteRevert(true, "boom");

        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit NativeActionReverted(address(nativeModule), abi.encodeWithSignature("Error(string)", "boom"));
        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit ActionFailed(NATIVE, NATIVE_ACTION_TYPE, VALUE, "Module execution reverted", executor);

        vm.prank(executor);
        bool success = paymentRails.executeAction(NATIVE, VALUE);

        assertFalse(success, "success");
        assertEq(address(paymentRails).balance, VALUE, "value must be rolled back to the rails");
        assertEq(address(nativeModule).balance, 0, "module must hold nothing");
    }

    function test_RevertWhen_TheModuleReturnsSuccessFalse() external givenNativeConfigured {
        _sendNative(executor, VALUE);
        nativeModule.setReturnFalse(true);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.PaymentRails_NativeModuleReturnedFailure.selector, "Mock refused")
        );
        paymentRails.executeAction(NATIVE, VALUE);

        assertEq(address(paymentRails).balance, VALUE, "value must stay on the rails");
        assertEq(address(nativeModule).balance, 0, "module must hold nothing");
    }

    function test_WhenCalledByANonOwner() external givenNativeConfigured {
        _sendNative(executor, VALUE);

        vm.prank(nonOwner);
        assertTrue(paymentRails.executeAction(NATIVE, VALUE));
        assertEq(address(nativeModule).balance, VALUE);
    }

    function test_GivenValueArrivedWithoutCallingReceive() external givenNativeConfigured {
        // vm.deal models value that arrives without running receive()
        vm.deal(address(paymentRails), VALUE);

        assertTrue(paymentRails.executeAction(NATIVE, VALUE));
        assertEq(address(nativeModule).balance, VALUE);
        assertEq(address(paymentRails).balance, 0);
    }

    function test_WhenAmountEqualsTheFullBalance() external givenNativeConfigured {
        _sendNative(executor, VALUE);

        assertTrue(paymentRails.executeAction(NATIVE, VALUE));
        assertEq(address(paymentRails).balance, 0, "rails must be drained");
    }

    function testFuzz_WhenAmountIsBetweenMinBalanceAndBalance(
        uint256 balance,
        uint256 amount
    )
        external
        givenNativeConfigured
    {
        balance = bound(balance, NATIVE_MIN, 1_000_000 ether);
        amount = bound(amount, NATIVE_MIN, balance);
        _sendNative(executor, balance);

        assertTrue(paymentRails.executeAction(NATIVE, amount));
        assertEq(address(nativeModule).balance, amount);
        assertEq(address(paymentRails).balance, balance - amount);
    }
}
