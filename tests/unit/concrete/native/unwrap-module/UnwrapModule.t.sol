// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { UnwrapModuleBase, NoReceiveCaller } from "./UnwrapModuleBase.t.sol";
import { UnwrapModule } from "../../../../../src/modules/native/UnwrapModule.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";

contract UnwrapModuleTest is UnwrapModuleBase {
    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    function test_Constructor_RevertWhen_WrappedNativeIsZeroAddress() external {
        vm.expectRevert(Errors.UnwrapModule_ZeroWrappedNative.selector);
        new UnwrapModule(address(0));
    }

    function test_Constructor_RevertWhen_WrappedNativeHasNoCode() external {
        address eoa = makeAddr("eoa");
        vm.expectRevert(abi.encodeWithSelector(Errors.UnwrapModule_WrappedNativeNotContract.selector, eoa));
        new UnwrapModule(eoa);
    }

    function test_Constructor_WhenWrappedNativeIsAContract() external view {
        assertEq(module.wrappedNative(), address(weth));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    RECEIVE
    //////////////////////////////////////////////////////////////////////////*/

    function test_Receive_WhenValueComesFromTheWrapper() external {
        vm.deal(address(weth), 1 ether);
        vm.prank(address(weth));
        (bool ok,) = address(module).call{ value: 1 ether }("");
        assertTrue(ok);
        assertEq(address(module).balance, 1 ether);
    }

    function test_Receive_RevertWhen_ValueComesFromAnyoneElse() external {
        address stranger = makeAddr("stranger");
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool ok, bytes memory ret) = address(module).call{ value: 1 ether }("");
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(Errors.UnwrapModule_UnexpectedNativeSender.selector, stranger));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    EXECUTE
    //////////////////////////////////////////////////////////////////////////*/

    function test_Execute_WhenTokenIsNotWrappedNative() external {
        DataTypes.ExecutionResult memory result = module.execute(address(token), DEFAULT_AMOUNT, "");
        assertFalse(result.success);
        assertEq(result.failureReason, "Only wrapped native supported");
    }

    function test_Execute_WhenAmountIsZero() external {
        DataTypes.ExecutionResult memory result = module.execute(address(weth), 0, "");
        assertFalse(result.success);
        assertEq(result.failureReason, "Zero amount");
    }

    function test_Execute_WhenCallerHasInsufficientBalance() external {
        vm.prank(makeAddr("broke"));
        DataTypes.ExecutionResult memory result = module.execute(address(weth), DEFAULT_AMOUNT, "");
        assertFalse(result.success);
        assertEq(result.failureReason, "Insufficient balance");
    }

    function test_Execute_WhenCallerHasNotApprovedTheModule() external {
        weth.approve(address(module), 0);
        DataTypes.ExecutionResult memory result = module.execute(address(weth), DEFAULT_AMOUNT, "");
        assertFalse(result.success);
        assertEq(result.failureReason, "Transfer failed");
    }

    function test_Execute_WhenCallerCannotTakeNativeValue() external {
        NoReceiveCaller caller = new NoReceiveCaller();
        weth.transfer(address(caller), DEFAULT_AMOUNT);
        vm.prank(address(caller));
        weth.approve(address(module), DEFAULT_AMOUNT);

        vm.prank(address(caller));
        DataTypes.ExecutionResult memory result = module.execute(address(weth), DEFAULT_AMOUNT, "");

        assertFalse(result.success, "success");
        assertEq(result.failureReason, "Native transfer failed", "failureReason");
        assertEq(weth.balanceOf(address(caller)), DEFAULT_AMOUNT, "wrapped balance returned");
        assertEq(address(module).balance, 0, "module native");
        assertEq(weth.balanceOf(address(module)), 0, "module wrapped");
    }

    function test_Execute_WhenAllChecksPass() external {
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 nativeBefore = address(this).balance;

        vm.expectEmit(true, false, false, true, address(module));
        emit Unwrapped(address(this), DEFAULT_AMOUNT);

        DataTypes.ExecutionResult memory result = module.execute(address(weth), DEFAULT_AMOUNT, "");

        assertTrue(result.success, "success");
        assertEq(result.amountOut, DEFAULT_AMOUNT, "amountOut");
        assertEq(result.outputToken, NATIVE, "outputToken");
        assertEq(wethBefore - weth.balanceOf(address(this)), DEFAULT_AMOUNT, "wrapped burned from caller");
        assertEq(address(this).balance - nativeBefore, DEFAULT_AMOUNT, "native delivered to caller");
        assertEq(address(module).balance, 0, "module native");
        assertEq(weth.balanceOf(address(module)), 0, "module wrapped");
    }

    function testFuzz_Execute_WhenAnyNonZeroAmountIsUnwrapped(uint256 amount) external {
        amount = bound(amount, 1, 50 ether);
        uint256 nativeBefore = address(this).balance;

        assertTrue(module.execute(address(weth), amount, "").success);

        assertEq(address(this).balance - nativeBefore, amount);
        assertEq(address(module).balance, 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    VALIDATE
    //////////////////////////////////////////////////////////////////////////*/

    function test_Validate_WhenTokenIsNotWrappedNative() external view {
        (bool ok, string memory reason) = module.validate(address(token), DEFAULT_AMOUNT, "");
        assertFalse(ok);
        assertEq(reason, "Only wrapped native supported");
    }

    function test_Validate_WhenAmountIsZero() external view {
        (bool ok, string memory reason) = module.validate(address(weth), 0, "");
        assertFalse(ok);
        assertEq(reason, "Zero amount");
    }

    function test_Validate_WhenCallerHasInsufficientBalance() external {
        vm.prank(makeAddr("broke"));
        (bool ok, string memory reason) = module.validate(address(weth), DEFAULT_AMOUNT, "");
        assertFalse(ok);
        assertEq(reason, "Insufficient balance");
    }

    function test_Validate_WhenAllChecksPass() external view {
        (bool ok, string memory reason) = module.validate(address(weth), DEFAULT_AMOUNT, "");
        assertTrue(ok);
        assertEq(reason, "");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        ESTIMATE OUTPUT / MODULE TYPE
    //////////////////////////////////////////////////////////////////////////*/

    function test_EstimateOutput() external view {
        (uint256 estimated, address outputToken) = module.estimateOutput(address(weth), DEFAULT_AMOUNT, "");
        assertEq(estimated, DEFAULT_AMOUNT);
        assertEq(outputToken, NATIVE);
    }

    function test_ModuleType() external view {
        assertEq(module.moduleType(), "UNWRAP");
    }
}
