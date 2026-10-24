// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";

contract PaymentRailsPreviewExecutionNativeTest is PaymentRailsBase {
    uint256 internal constant VALUE = 3 ether;

    function test_RevertWhen_TheNativeKeyIsNotConfigured() external {
        _sendNative(executor, VALUE);

        vm.expectRevert(Errors.PaymentRails_NoActionConfigured.selector);
        paymentRails.previewExecution(NATIVE);
    }

    function test_RevertGiven_NativeBalanceIsZero() external givenNativeConfigured {
        vm.expectRevert(Errors.PaymentRails_ZeroAmount.selector);
        paymentRails.previewExecution(NATIVE);
    }

    function test_RevertGiven_NativeBalanceIsBelowMinBalance() external givenNativeConfigured {
        _sendNative(executor, NATIVE_MIN - 1);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.PaymentRails_BelowMinimumBalance.selector, NATIVE_MIN - 1, NATIVE_MIN)
        );
        paymentRails.previewExecution(NATIVE);
    }

    function test_RevertWhen_ModuleValidationFails() external givenNativeConfigured {
        _sendNative(executor, VALUE);
        nativeModule.setValidationResult(false, "Mock says no");

        vm.expectRevert("Mock says no");
        paymentRails.previewExecution(NATIVE);
    }

    function test_GivenANativeRouteWithSufficientBalance() external givenNativeConfigured {
        _sendNative(executor, VALUE);

        (uint256 estimatedOutput, address outputToken) = paymentRails.previewExecution(NATIVE);

        assertEq(estimatedOutput, VALUE, "estimatedOutput");
        assertEq(outputToken, NATIVE, "outputToken");
    }
}
