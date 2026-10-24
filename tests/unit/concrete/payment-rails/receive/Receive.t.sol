// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { StipendSender } from "../../../../shared/mocks/NativeMocks.sol";

contract PaymentRailsReceiveTest is PaymentRailsBase {
    uint256 internal constant VALUE = 1 ether;

    StipendSender internal sender;

    function setUp() public override {
        super.setUp();
        sender = new StipendSender();
        vm.deal(address(sender), 100 ether);
    }

    function test_RevertGiven_NativeIngressIsDisabled() external {
        PaymentRails disabled = new PaymentRails(owner, address(0));
        vm.deal(executor, VALUE);

        vm.prank(executor);
        (bool ok, bytes memory ret) = address(disabled).call{ value: VALUE }("");

        assertFalse(ok, "value transfer must bounce when ingress is disabled");
        assertEq(ret, abi.encodeWithSelector(Errors.PaymentRails_NativeNotSupported.selector));
        assertEq(address(disabled).balance, 0, "nothing may strand");
        assertEq(executor.balance, VALUE, "sender keeps the value");
    }

    function test_RevertWhen_ValueIsZero() external {
        vm.recordLogs();

        vm.prank(executor);
        (bool ok, bytes memory ret) = address(paymentRails).call{ value: 0 }("");

        assertFalse(ok, "zero-value call must revert");
        assertEq(ret, abi.encodeWithSelector(Errors.PaymentRails_ZeroAmount.selector));
        assertEq(vm.getRecordedLogs().length, 0, "no NativeReceived may be emitted for zero value");
        assertFalse(sender.sendWithSend(payable(address(paymentRails)), 0), "zero-value send() must fail");
    }

    function test_WhenValueIsSentWithCall() external {
        uint256 wrappedBefore = weth.balanceOf(address(paymentRails));
        vm.deal(executor, VALUE);

        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit NativeReceived(executor, VALUE);

        vm.prank(executor);
        (bool ok,) = address(paymentRails).call{ value: VALUE }("");
        assertTrue(ok);

        assertEq(address(paymentRails).balance, VALUE);
        assertEq(weth.balanceOf(address(paymentRails)), wrappedBefore);
    }

    function test_WhenValueIsSentWithTransfer() external {
        // transfer() forwards only the 2300-gas stipend
        sender.sendWithTransfer(payable(address(paymentRails)), VALUE);

        assertEq(address(paymentRails).balance, VALUE);
    }

    function test_WhenValueIsSentWithSend() external {
        bool ok = sender.sendWithSend(payable(address(paymentRails)), VALUE);

        assertTrue(ok, "send() must succeed within the stipend");
        assertEq(address(paymentRails).balance, VALUE);
    }

    function test_WhenValueComesFromTheWrapper() external {
        vm.deal(address(weth), VALUE);
        vm.recordLogs();

        vm.prank(address(weth));
        (bool ok,) = address(paymentRails).call{ value: VALUE }("");

        assertTrue(ok, "the wrapper's payout must be accepted");
        assertEq(address(paymentRails).balance, VALUE);
        assertEq(vm.getRecordedLogs().length, 0, "the wrapper's payout is not a receipt");
    }

    function test_RevertWhen_CalldataIsNonEmpty() external {
        vm.deal(executor, VALUE);

        vm.prank(executor);
        (bool ok,) = address(paymentRails).call{ value: VALUE }(abi.encodeWithSignature("doesNotExist()"));

        assertFalse(ok);
        assertEq(address(paymentRails).balance, 0);
    }

    function testFuzz_WhenAnyNonZeroValueIsSent(uint256 value) external {
        value = bound(value, 1, 1_000_000 ether);

        _sendNative(executor, value);

        assertEq(address(paymentRails).balance, value);
    }
}
