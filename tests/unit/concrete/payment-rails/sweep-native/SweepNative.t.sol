// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { RejectingRecipient, ReentrantSweepRecipient, ShortMintWETH9 } from "../../../../shared/mocks/NativeMocks.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Vm } from "forge-std/src/Vm.sol";

/// @dev Native is funded before the owner prank: the funding helper issues its own prank.
contract PaymentRailsSweepNativeTest is PaymentRailsBase {
    uint256 internal constant VALUE = 3 ether;

    function test_RevertWhen_CallerIsNotOwner() external {
        _sendNative(executor, VALUE);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        paymentRails.sweepNative(recipient);
    }

    function test_RevertWhen_RecipientIsZeroAddress() external {
        _sendNative(executor, VALUE);

        vm.expectRevert(Errors.PaymentRails_ZeroRecipient.selector);
        vm.prank(owner);
        paymentRails.sweepNative(address(0));
    }

    function test_RevertGiven_NoNativeAndNoWrappedBalance() external {
        vm.expectRevert(Errors.PaymentRails_ZeroNativeBalance.selector);
        vm.prank(owner);
        paymentRails.sweepNative(recipient);
    }

    function test_RevertGiven_TheWrapperPaysOutLessThanTheWrappedBalance() external {
        ShortMintWETH9 shortWrapper = new ShortMintWETH9();
        PaymentRails rails = new PaymentRails(owner, address(shortWrapper));
        deal(address(shortWrapper), address(rails), VALUE);
        vm.deal(address(shortWrapper), VALUE);

        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRails_UnwrapAmountMismatch.selector, VALUE, VALUE / 2));
        vm.prank(owner);
        rails.sweepNative(recipient);
    }

    function test_RevertWhen_RecipientRejects() external {
        RejectingRecipient rejecting = new RejectingRecipient();
        _sendNative(executor, VALUE);
        paymentRails.wrapNative();
        _sendNative(executor, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRails_NativeTransferFailed.selector, address(rejecting)));
        vm.prank(owner);
        paymentRails.sweepNative(address(rejecting));

        assertEq(address(paymentRails).balance, 1 ether, "native must be unchanged");
        assertEq(weth.balanceOf(address(paymentRails)), VALUE, "wrapped must be unchanged");
    }

    function test_GivenOnlyNativeBalance() external {
        _sendNative(executor, VALUE);

        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit NativeSwept(recipient, VALUE);

        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(recipient);

        assertEq(amount, VALUE, "returned amount");
        assertEq(recipient.balance, VALUE, "recipient balance");
        assertEq(address(paymentRails).balance, 0, "rails drained");
    }

    function test_GivenOnlyWrappedBalance() external {
        _sendNative(executor, VALUE);
        paymentRails.wrapNative();

        vm.recordLogs();
        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(recipient);

        bytes32 receivedSig = keccak256("NativeReceived(address,uint256)");
        bytes32 sweptSig = keccak256("NativeSwept(address,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawSwept;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(paymentRails)) continue;
            assertTrue(logs[i].topics[0] != receivedSig, "the wrapper payout must not be logged as a receipt");
            if (logs[i].topics[0] == sweptSig) sawSwept = true;
        }
        assertTrue(sawSwept, "NativeSwept must be emitted");

        assertEq(amount, VALUE, "returned amount");
        assertEq(weth.balanceOf(address(paymentRails)), 0, "wrapped unwrapped in full");
        assertEq(recipient.balance, VALUE, "recipient balance");
        assertEq(address(paymentRails).balance, 0, "rails drained");
    }

    function test_GivenBothNativeAndWrappedBalance() external {
        _sendNative(executor, VALUE);
        paymentRails.wrapNative();
        _sendNative(executor, 1 ether);

        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(recipient);

        assertEq(amount, VALUE + 1 ether, "returned amount is the sum");
        assertEq(recipient.balance, VALUE + 1 ether, "recipient receives the sum");
        assertEq(address(paymentRails).balance, 0, "native drained");
        assertEq(weth.balanceOf(address(paymentRails)), 0, "wrapped drained");
    }

    function test_WhenRecipientReEntersWrapNative() external {
        ReentrantSweepRecipient reentrant = new ReentrantSweepRecipient();
        _sendNative(executor, VALUE);

        vm.prank(owner);
        paymentRails.sweepNative(address(reentrant));

        assertTrue(reentrant.reentrancyBlocked(), "nested wrapNative must hit the reentrancy guard");
        assertEq(address(reentrant).balance, VALUE, "recipient receives the full amount");
        assertEq(address(paymentRails).balance, 0);
        assertEq(weth.balanceOf(address(paymentRails)), 0, "nothing was wrapped during the sweep");
    }

    function test_GivenNativeIngressIsDisabled() external {
        PaymentRails disabled = new PaymentRails(owner, address(0));
        // vm.deal models value that arrives without running receive()
        vm.deal(address(disabled), VALUE);

        vm.prank(owner);
        uint256 amount = disabled.sweepNative(recipient);

        assertEq(amount, VALUE);
        assertEq(recipient.balance, VALUE, "force-fed value must be recoverable");
        assertEq(address(disabled).balance, 0);
    }

    function test_GivenValueArrivedWithoutCallingReceive() external {
        vm.deal(address(paymentRails), VALUE);
        _sendNative(executor, 1 ether);

        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(recipient);

        assertEq(amount, VALUE + 1 ether);
        assertEq(recipient.balance, VALUE + 1 ether);
    }

    function testFuzz_WhenNativeAndWrappedBalancesAreArbitrary(uint256 native, uint256 wrapped) external {
        native = bound(native, 0, 1_000_000 ether);
        wrapped = bound(wrapped, 0, 1_000_000 ether);
        vm.assume(native + wrapped > 0);
        if (wrapped > 0) {
            _sendNative(executor, wrapped);
            paymentRails.wrapNative();
        }
        if (native > 0) _sendNative(executor, native);

        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(recipient);

        assertEq(amount, native + wrapped, "returned amount");
        assertEq(recipient.balance, native + wrapped, "recipient receives the sum");
        assertEq(address(paymentRails).balance, 0, "native drained");
        assertEq(weth.balanceOf(address(paymentRails)), 0, "wrapped drained");
    }
}
