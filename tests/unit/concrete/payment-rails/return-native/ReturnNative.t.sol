// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { Vm } from "forge-std/src/Vm.sol";

contract PaymentRailsReturnNativeTest is PaymentRailsBase {
    uint256 internal constant VALUE = 1 ether;

    function test_RevertWhen_CallerIsNotTheConfiguredModule() external givenTokenConfigured {
        vm.deal(executor, VALUE);

        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRails_UnexpectedNativeDepositor.selector, executor));
        vm.prank(executor);
        paymentRails.returnNative{ value: VALUE }(address(token));
    }

    function test_RevertWhen_TheSourceTokenHasNoConfiguration() external {
        vm.deal(address(actionModule), VALUE);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.PaymentRails_UnexpectedNativeDepositor.selector, address(actionModule))
        );
        vm.prank(address(actionModule));
        paymentRails.returnNative{ value: VALUE }(address(token));
    }

    function test_RevertWhen_ValueIsZero() external givenTokenConfigured {
        vm.expectRevert(Errors.PaymentRails_ZeroAmount.selector);
        vm.prank(address(actionModule));
        paymentRails.returnNative{ value: 0 }(address(token));
    }

    function test_WhenTheConfiguredModuleReturnsValue() external givenTokenConfigured {
        vm.deal(address(actionModule), VALUE);
        vm.recordLogs();

        vm.prank(address(actionModule));
        paymentRails.returnNative{ value: VALUE }(address(token));

        assertEq(address(paymentRails).balance, VALUE, "native balance");
        bytes32 returnedSig = keccak256("NativeReturned(address,address,uint256)");
        bytes32 receivedSig = keccak256("NativeReceived(address,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawReturned;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(paymentRails)) continue;
            assertTrue(logs[i].topics[0] != receivedSig, "a module return must not be logged as a payer receipt");
            if (logs[i].topics[0] == returnedSig) {
                sawReturned = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(token), "source token");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), address(actionModule), "module");
                assertEq(abi.decode(logs[i].data, (uint256)), VALUE, "amount");
            }
        }
        assertTrue(sawReturned, "NativeReturned must be emitted");
    }

    function testFuzz_WhenAnyNonZeroValueIsReturned(uint256 value) external givenTokenConfigured {
        value = bound(value, 1, 1_000_000 ether);
        vm.deal(address(actionModule), value);

        vm.prank(address(actionModule));
        paymentRails.returnNative{ value: value }(address(token));

        assertEq(address(paymentRails).balance, value);
    }
}
