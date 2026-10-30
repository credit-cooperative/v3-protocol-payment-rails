// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { StipendSender } from "../../../../shared/mocks/NativeMocks.sol";
import { VmSafe } from "forge-std/src/Vm.sol";

contract PaymentRailsReceiveTest is PaymentRailsBase {
    uint256 internal constant VALUE = 1 ether;

    StipendSender internal sender;

    function setUp() public override {
        super.setUp();
        sender = new StipendSender();
        vm.deal(address(sender), 100 ether);
    }

    function test_WhenValueIsZero() external {
        vm.recordLogs();

        vm.prank(executor);
        (bool ok,) = address(paymentRails).call{ value: 0 }("");

        assertTrue(ok, "zero-value call must not revert a payer's batch");
        assertEq(vm.getRecordedLogs().length, 0, "no NativeReceived may be emitted for zero value");
        assertTrue(sender.sendWithSend(payable(address(paymentRails)), 0), "zero-value send() must succeed");
        assertEq(address(paymentRails).balance, 0);
    }

    function test_WhenValueIsSentWithCall() external {
        vm.deal(executor, VALUE);

        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit NativeReceived(executor, VALUE);

        vm.prank(executor);
        (bool ok,) = address(paymentRails).call{ value: VALUE }("");
        assertTrue(ok);

        assertEq(address(paymentRails).balance, VALUE);
    }

    /// @dev Coverage instrumentation disables the optimizer and inflates receive() past the stipend, so the
    ///      stipend assertions run only on the optimized artifact (forge test, the live fork suites, the harnesses).
    modifier skipUnderCoverage() {
        if (vm.isContext(VmSafe.ForgeContext.Coverage)) vm.skip(true);
        _;
    }

    function test_WhenValueIsSentWithTransfer() external skipUnderCoverage {
        // transfer() forwards only the 2300-gas stipend
        sender.sendWithTransfer(payable(address(paymentRails)), VALUE);

        assertEq(address(paymentRails).balance, VALUE);
    }

    function test_WhenValueIsSentWithSend() external skipUnderCoverage {
        bool ok = sender.sendWithSend(payable(address(paymentRails)), VALUE);

        assertTrue(ok, "send() must succeed within the stipend");
        assertEq(address(paymentRails).balance, VALUE);
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
