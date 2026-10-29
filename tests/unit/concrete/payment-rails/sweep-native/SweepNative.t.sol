// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { RejectingRecipient, ReentrantSweepRecipient } from "../../../../shared/mocks/NativeMocks.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @dev Native is funded before the owner prank: the funding helper issues its own prank.
contract PaymentRailsSweepNativeTest is PaymentRailsBase {
    uint256 internal constant VALUE = 3 ether;

    function test_RevertWhen_CallerIsNotTheOwner() external {
        _sendNative(executor, VALUE);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        paymentRails.sweepNative(nonOwner);

        assertEq(address(paymentRails).balance, VALUE, "a stranger's sweep attempt must move nothing");
    }

    function test_RevertWhen_RecipientIsZeroAddress() external {
        _sendNative(executor, VALUE);

        vm.expectRevert(Errors.PaymentRails_ZeroRecipient.selector);
        vm.prank(owner);
        paymentRails.sweepNative(address(0));
    }

    function test_RevertGiven_NoNativeBalance() external {
        vm.expectRevert(Errors.PaymentRails_ZeroNativeBalance.selector);
        vm.prank(owner);
        paymentRails.sweepNative(recipient);
    }

    function test_RevertWhen_RecipientRejects() external {
        RejectingRecipient rejecting = new RejectingRecipient();
        _sendNative(executor, VALUE);

        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRails_NativeTransferFailed.selector, address(rejecting)));
        vm.prank(owner);
        paymentRails.sweepNative(address(rejecting));

        assertEq(address(paymentRails).balance, VALUE, "native must be unchanged");
    }

    function test_GivenANativeBalance() external {
        _sendNative(executor, VALUE);

        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit NativeSwept(recipient, VALUE);

        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(recipient);

        assertEq(amount, VALUE, "returned amount");
        assertEq(recipient.balance, VALUE, "recipient balance");
        assertEq(address(paymentRails).balance, 0, "rails drained");
    }

    function test_WhenANonOwnerRecipientReEntersSweepNative() external {
        ReentrantSweepRecipient reentrant = new ReentrantSweepRecipient();
        _sendNative(executor, VALUE);

        vm.prank(owner);
        paymentRails.sweepNative(address(reentrant));

        // The recipient is not the owner, so the nested call fails the owner check before the guard.
        assertEq(reentrant.rejectedWith(), Ownable.OwnableUnauthorizedAccount.selector, "re-entry must be rejected");
        assertEq(address(reentrant).balance, VALUE, "recipient receives the full amount");
        assertEq(address(paymentRails).balance, 0);
    }

    function test_WhenTheOwnerReEntersSweepNativeAsRecipient() external {
        // The recipient is also the owner, so the nested call passes the owner check and meets the guard.
        ReentrantSweepRecipient reentrant = new ReentrantSweepRecipient();
        PaymentRails rails = new PaymentRails(address(reentrant));
        vm.deal(address(rails), VALUE);

        vm.prank(address(reentrant));
        uint256 amount = rails.sweepNative(address(reentrant));

        assertEq(reentrant.rejectedWith(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector, "guard must reject");
        assertEq(amount, VALUE);
        assertEq(address(reentrant).balance, VALUE, "recipient receives the full amount once");
        assertEq(address(rails).balance, 0);
    }

    function test_GivenValueArrivedWithoutCallingReceive() external {
        // vm.deal models value that arrives without running receive()
        vm.deal(address(paymentRails), VALUE);
        _sendNative(executor, 1 ether);

        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(recipient);

        assertEq(amount, VALUE + 1 ether);
        assertEq(recipient.balance, VALUE + 1 ether);
    }

    function test_GivenTokenBalancesAreHeld() external {
        uint256 tokenBefore = token.balanceOf(address(paymentRails));
        _sendNative(executor, VALUE);

        vm.prank(owner);
        paymentRails.sweepNative(recipient);

        assertEq(token.balanceOf(address(paymentRails)), tokenBefore, "ERC20 balances are not part of the sweep");
    }

    function testFuzz_WhenTheNativeBalanceIsAnyNonZeroAmount(uint256 value) external {
        value = bound(value, 1, 1_000_000 ether);
        _sendNative(executor, value);

        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(recipient);

        assertEq(amount, value, "returned amount");
        assertEq(recipient.balance, value, "recipient receives the whole balance");
        assertEq(address(paymentRails).balance, 0, "rails drained");
    }
}
