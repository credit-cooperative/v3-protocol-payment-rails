// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { MockWETH9 } from "../../../../shared/mocks/MockWETH9.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract PaymentRailsConstructorTest is Test {
    MockWETH9 internal weth;
    address internal expectedOwner;

    function setUp() public {
        weth = new MockWETH9();
        expectedOwner = makeAddr("owner");
    }

    function test_RevertWhen_InitialOwnerIsZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new PaymentRails(address(0), address(weth));
    }

    function test_RevertWhen_WrappedNativeHasNoCode() external {
        address eoa = makeAddr("notAContract");
        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRails_WrappedNativeNotContract.selector, eoa));
        new PaymentRails(expectedOwner, eoa);
    }

    function test_WhenWrappedNativeIsZeroAddress() external {
        PaymentRails paymentRails = new PaymentRails(expectedOwner, address(0));
        assertEq(paymentRails.owner(), expectedOwner);
        assertEq(paymentRails.wrappedNative(), address(0));
    }

    function test_WhenWrappedNativeIsAContract() external {
        PaymentRails paymentRails = new PaymentRails(expectedOwner, address(weth));
        assertEq(paymentRails.owner(), expectedOwner);
        assertEq(paymentRails.pendingOwner(), address(0));
        assertEq(paymentRails.wrappedNative(), address(weth));
    }
}
