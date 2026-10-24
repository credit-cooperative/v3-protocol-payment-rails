// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
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

    /// @dev Coverage instrumentation disables the optimizer and inflates receive() past the stipend, so the
    ///      stipend assertions run only on the optimized artifact (forge test, the live fork suites, the harnesses).
    modifier skipUnderCoverage() {
        if (vm.isContext(VmSafe.ForgeContext.Coverage)) vm.skip(true);
        _;
    }

    function test_RevertWhen_ValueIsZero() external {
        vm.prank(executor);
        (bool ok, bytes memory ret) = address(paymentRails).call{ value: 0 }("");

        assertFalse(ok, "zero-value call must revert");
        assertEq(ret, abi.encodeWithSelector(Errors.PaymentRails_ZeroAmount.selector));
        assertFalse(sender.sendWithSend(payable(address(paymentRails)), 0), "zero-value send() must fail");
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
