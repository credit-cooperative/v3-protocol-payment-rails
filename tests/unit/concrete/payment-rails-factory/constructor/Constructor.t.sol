// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { PaymentRailsFactory } from "../../../../../src/core/PaymentRailsFactory.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { MockWETH9 } from "../../../../shared/mocks/MockWETH9.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract PaymentRailsFactoryConstructorTest is Test {
    MockWETH9 internal weth;
    address internal owner;

    function setUp() public {
        weth = new MockWETH9();
        owner = makeAddr("owner");
    }

    function test_RevertWhen_InitialOwnerIsZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new PaymentRailsFactory(address(0), address(weth));
    }

    function test_RevertWhen_WrappedNativeHasNoCode() external {
        address eoa = makeAddr("notAContract");
        vm.expectRevert(abi.encodeWithSelector(Errors.PaymentRailsFactory_WrappedNativeNotContract.selector, eoa));
        new PaymentRailsFactory(owner, eoa);
    }

    function test_WhenWrappedNativeIsZeroAddress() external {
        PaymentRailsFactory factory = new PaymentRailsFactory(owner, address(0));
        assertEq(factory.owner(), owner);
        assertEq(factory.wrappedNative(), address(0));
    }

    function test_WhenWrappedNativeIsAContract() external {
        PaymentRailsFactory factory = new PaymentRailsFactory(owner, address(weth));
        assertEq(factory.owner(), owner);
        assertEq(factory.wrappedNative(), address(weth));
    }
}
