// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { ReentrantWETH9, ShortMintWETH9 } from "../../../../shared/mocks/NativeMocks.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PaymentRailsWrapNativeTest is PaymentRailsBase {
    uint256 internal constant VALUE = 3 ether;

    function test_RevertWhen_CallerIsNotTheOwner() external {
        _sendNative(executor, VALUE);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        paymentRails.wrapNative();

        assertEq(address(paymentRails).balance, VALUE, "a stranger's wrap attempt must move nothing");
        assertEq(weth.balanceOf(address(paymentRails)), 0);
    }

    function test_RevertGiven_NativeIngressIsDisabled() external {
        PaymentRails disabled = new PaymentRails(owner, address(0));

        vm.expectRevert(Errors.PaymentRails_NativeNotSupported.selector);
        vm.prank(owner);
        disabled.wrapNative();
    }

    function test_RevertGiven_NativeBalanceIsZero() external {
        vm.expectRevert(Errors.PaymentRails_ZeroNativeBalance.selector);
        vm.prank(owner);
        paymentRails.wrapNative();
    }

    function test_RevertGiven_TheWrapperCreditsLessThanTheDeposit() external {
        ShortMintWETH9 shortMint = new ShortMintWETH9();
        PaymentRails rails = new PaymentRails(owner, address(shortMint));
        vm.deal(address(rails), VALUE);

        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRails_WrapAmountMismatch.selector, VALUE, VALUE / 2));
        vm.prank(owner);
        rails.wrapNative();

        assertEq(address(rails).balance, VALUE, "a mis-set wrapper must not be able to burn the deposit");
    }

    function test_GivenNativeBalanceIsNonZero() external {
        _sendNative(executor, VALUE);
        uint256 wrappedBefore = weth.balanceOf(address(paymentRails));
        uint256 wrapperNativeBefore = address(weth).balance;

        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit NativeWrapped(owner, VALUE);

        vm.prank(owner);
        uint256 amount = paymentRails.wrapNative();

        assertEq(amount, VALUE);
        assertEq(address(paymentRails).balance, 0);
        assertEq(weth.balanceOf(address(paymentRails)) - wrappedBefore, VALUE);
        assertEq(address(weth).balance - wrapperNativeBefore, VALUE);
    }

    function test_GivenValueArrivedWithoutCallingReceive() external {
        // vm.deal models value that arrives without running receive()
        vm.deal(address(paymentRails), VALUE);
        _sendNative(executor, 1 ether);

        vm.prank(owner);
        uint256 amount = paymentRails.wrapNative();

        assertEq(amount, VALUE + 1 ether);
        assertEq(address(paymentRails).balance, 0);
        assertEq(weth.balanceOf(address(paymentRails)), VALUE + 1 ether);
    }

    function test_WhenTheWrapperReEntersWrapNativeAsTheOwner() external {
        // The wrapper is also the owner, so the nested call passes the owner check and meets the guard.
        ReentrantWETH9 reentrant = new ReentrantWETH9();
        PaymentRails rails = new PaymentRails(address(reentrant), address(reentrant));
        vm.deal(address(rails), VALUE);

        vm.prank(address(reentrant));
        uint256 amount = rails.wrapNative();

        assertEq(reentrant.rejectedWith(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector, "guard must reject");
        assertEq(amount, VALUE);
        assertEq(address(rails).balance, 0);
        assertEq(reentrant.balanceOf(address(rails)), VALUE);
    }

    function test_WhenTheWrapperReEntersWrapNativeAsAStranger() external {
        ReentrantWETH9 reentrant = new ReentrantWETH9();
        PaymentRails rails = new PaymentRails(owner, address(reentrant));
        vm.deal(address(rails), VALUE);

        vm.prank(owner);
        uint256 amount = rails.wrapNative();

        assertEq(reentrant.rejectedWith(), Ownable.OwnableUnauthorizedAccount.selector, "owner check must reject");
        assertEq(amount, VALUE);
        assertEq(address(rails).balance, 0);
        assertEq(reentrant.balanceOf(address(rails)), VALUE);
    }

    function test_GivenWrappedNativeIsConfiguredForAnAction() external {
        vm.prank(owner);
        paymentRails.configureToken(address(weth), ACTION_TYPE, address(actionModule), 0, _defaultModuleParams(), true);
        _sendNative(executor, VALUE);
        vm.prank(owner);
        paymentRails.wrapNative();

        vm.prank(executor);
        bool success = paymentRails.executeAction(address(weth), VALUE);

        assertTrue(success);
        assertEq(weth.balanceOf(address(paymentRails)), 0, "wrapped balance must leave the rails");
        assertEq(weth.balanceOf(address(actionModule)), VALUE, "module must have pulled the wrapped balance");
        assertEq(weth.allowance(address(paymentRails), address(actionModule)), 0, "approval must be revoked");
    }

    function testFuzz_WhenNativeBalanceIsAnyNonZeroAmount(uint256 value) external {
        value = bound(value, 1, 1_000_000 ether);
        _sendNative(executor, value);

        vm.prank(owner);
        uint256 amount = paymentRails.wrapNative();

        assertEq(amount, value);
        assertEq(address(paymentRails).balance, 0);
        assertEq(weth.balanceOf(address(paymentRails)), value);
    }
}
