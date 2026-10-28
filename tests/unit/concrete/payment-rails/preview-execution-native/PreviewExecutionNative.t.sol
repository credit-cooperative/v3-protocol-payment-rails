// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";

contract PaymentRailsPreviewExecutionNativeTest is PaymentRailsBase {
    uint256 internal constant PENDING = 3 ether;
    uint256 internal constant WETH_MIN = 1 ether;

    modifier givenWrappedConfigured() {
        vm.prank(owner);
        paymentRails.configureToken(
            address(weth), ACTION_TYPE, address(actionModule), WETH_MIN, _defaultModuleParams(), true
        );
        _;
    }

    function test_RevertGiven_NativeIsPendingAndTheWrappedBalanceIsZero() external givenWrappedConfigured {
        _sendNative(executor, PENDING);

        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRails_NativePendingWrap.selector, PENDING));
        paymentRails.previewExecution(address(weth));
    }

    function test_RevertGiven_NativeIsPendingAndTheWrappedBalanceIsBelowMinBalance() external givenWrappedConfigured {
        _sendNative(executor, WETH_MIN / 2);
        vm.prank(owner);
        paymentRails.wrapNative();
        _sendNative(executor, PENDING);

        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRails_NativePendingWrap.selector, PENDING));
        paymentRails.previewExecution(address(weth));
    }

    function test_GivenNativeIsPendingAndTheWrappedBalanceMeetsMinBalance() external givenWrappedConfigured {
        _sendNative(executor, WETH_MIN);
        vm.prank(owner);
        paymentRails.wrapNative();
        _sendNative(executor, PENDING);

        (uint256 estimated, address outputToken) = paymentRails.previewExecution(address(weth));

        assertEq(estimated, WETH_MIN, "preview reports only the routable wrapped balance");
        assertEq(outputToken, address(weth));
    }

    function test_RevertGiven_NativeIsPendingButWrappingWouldStillNotMeetMinBalance() external givenWrappedConfigured {
        // 0 wrapped + a little native < WETH_MIN: wrapping would not help, so the real reason is reported.
        _sendNative(executor, WETH_MIN / 4);

        vm.expectRevert(Errors.PaymentRails_ZeroAmount.selector);
        paymentRails.previewExecution(address(weth));

        // Some wrapped + a little native, still < WETH_MIN.
        vm.prank(owner);
        paymentRails.wrapNative();
        _sendNative(executor, WETH_MIN / 4);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.PaymentRails_BelowMinimumBalance.selector, WETH_MIN / 4, WETH_MIN)
        );
        paymentRails.previewExecution(address(weth));
    }

    modifier givenWrappedConfiguredWithZeroMin() {
        vm.prank(owner);
        paymentRails.configureToken(address(weth), ACTION_TYPE, address(actionModule), 0, _defaultModuleParams(), true);
        _;
    }

    function test_RevertGiven_MinBalanceIsZeroWithNativePendingAndNoWrappedBalance()
        external
        givenWrappedConfiguredWithZeroMin
    {
        _sendNative(executor, PENDING);

        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRails_NativePendingWrap.selector, PENDING));
        paymentRails.previewExecution(address(weth));
    }

    function test_GivenMinBalanceIsZeroWithNativePendingAndSomeWrappedBalance()
        external
        givenWrappedConfiguredWithZeroMin
    {
        _sendNative(executor, WETH_MIN / 2);
        vm.prank(owner);
        paymentRails.wrapNative();
        _sendNative(executor, PENDING);

        (uint256 estimated,) = paymentRails.previewExecution(address(weth));

        assertEq(estimated, WETH_MIN / 2, "with a zero minimum any wrapped balance previews on its own");
    }

    function test_RevertGiven_NoNativeIsPendingAndTheWrappedBalanceIsZero() external givenWrappedConfigured {
        vm.expectRevert(Errors.PaymentRails_ZeroAmount.selector);
        paymentRails.previewExecution(address(weth));
    }

    function test_GivenNativeIsPendingForADifferentToken() external givenTokenConfigured {
        _sendNative(executor, PENDING);

        (uint256 estimated,) = paymentRails.previewExecution(address(token));

        assertEq(estimated, INITIAL_BALANCE, "pending native must not touch other tokens' previews");
    }

    function test_GivenTheNativeHasBeenWrapped() external givenWrappedConfigured {
        _sendNative(executor, PENDING);
        vm.prank(owner);
        paymentRails.wrapNative();

        (uint256 estimated,) = paymentRails.previewExecution(address(weth));

        assertEq(estimated, PENDING, "after the wrap the full balance previews");
    }
}
