// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { WrapModuleBase } from "./WrapModuleBase.t.sol";
import { WrapModule } from "../../../../../src/modules/native/WrapModule.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { ShortMintWETH9 } from "../../../../shared/mocks/NativeMocks.sol";

contract WrapModuleTest is WrapModuleBase {
    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    function test_Constructor_RevertWhen_WrappedNativeIsZeroAddress() external {
        vm.expectRevert(Errors.WrapModule_ZeroWrappedNative.selector);
        new WrapModule(address(0));
    }

    function test_Constructor_RevertWhen_WrappedNativeHasNoCode() external {
        address eoa = makeAddr("eoa");
        vm.expectRevert(abi.encodeWithSelector(Errors.WrapModule_WrappedNativeNotContract.selector, eoa));
        new WrapModule(eoa);
    }

    function test_Constructor_WhenWrappedNativeIsAContract() external view {
        assertEq(module.wrappedNative(), address(weth));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 EXECUTE NATIVE
    //////////////////////////////////////////////////////////////////////////*/

    function test_ExecuteNative_RevertWhen_AmountIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.WrapModule_ValueMismatch.selector, 0, 0));
        vm.prank(paymentRails);
        module.executeNative{ value: 0 }(0, "");
    }

    function test_ExecuteNative_RevertWhen_ValueDiffersFromAmount() external {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.WrapModule_ValueMismatch.selector, DEFAULT_AMOUNT, DEFAULT_AMOUNT - 1)
        );
        vm.prank(paymentRails);
        module.executeNative{ value: DEFAULT_AMOUNT - 1 }(DEFAULT_AMOUNT, "");
    }

    function test_ExecuteNative_RevertWhen_TheWrapperCreditsLessThanTheDeposit() external {
        WrapModule shortModule = new WrapModule(address(new ShortMintWETH9()));

        vm.expectRevert(
            abi.encodeWithSelector(Errors.WrapModule_WrapAmountMismatch.selector, DEFAULT_AMOUNT, DEFAULT_AMOUNT / 2)
        );
        vm.prank(paymentRails);
        shortModule.executeNative{ value: DEFAULT_AMOUNT }(DEFAULT_AMOUNT, "");
    }

    function test_ExecuteNative_WhenTheWrapperCreditsOneToOne() external {
        vm.expectEmit(true, false, false, true, address(module));
        emit Wrapped(paymentRails, DEFAULT_AMOUNT);

        vm.prank(paymentRails);
        DataTypes.ExecutionResult memory result = module.executeNative{ value: DEFAULT_AMOUNT }(DEFAULT_AMOUNT, "");

        assertTrue(result.success, "success");
        assertEq(result.amountOut, DEFAULT_AMOUNT, "amountOut");
        assertEq(result.outputToken, address(weth), "outputToken");
        assertEq(weth.balanceOf(paymentRails), DEFAULT_AMOUNT, "caller wrapped balance");
        assertEq(address(module).balance, 0, "module native");
        assertEq(weth.balanceOf(address(module)), 0, "module wrapped");
    }

    function testFuzz_ExecuteNative_WhenAnyNonZeroValueIsWrapped(uint256 amount) external {
        amount = bound(amount, 1, 1_000_000 ether);
        vm.deal(paymentRails, amount);

        vm.prank(paymentRails);
        module.executeNative{ value: amount }(amount, "");

        assertEq(weth.balanceOf(paymentRails), amount);
        assertEq(address(module).balance, 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    EXECUTE
    //////////////////////////////////////////////////////////////////////////*/

    function test_Execute_ShouldReturnAFailedResult() external {
        vm.prank(paymentRails);
        DataTypes.ExecutionResult memory result = module.execute(address(token), DEFAULT_AMOUNT, "");

        assertFalse(result.success, "success");
        assertEq(result.failureReason, "Native input only", "failureReason");
        assertEq(result.outputToken, address(token), "outputToken");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    VALIDATE
    //////////////////////////////////////////////////////////////////////////*/

    function test_Validate_WhenTokenIsNotTheNativeSentinel() external {
        vm.prank(paymentRails);
        (bool ok, string memory reason) = module.validate(address(token), DEFAULT_AMOUNT, "");
        assertFalse(ok);
        assertEq(reason, "Native input only");
    }

    function test_Validate_WhenAmountIsZero() external {
        vm.prank(paymentRails);
        (bool ok, string memory reason) = module.validate(NATIVE, 0, "");
        assertFalse(ok);
        assertEq(reason, "Zero amount");
    }

    function test_Validate_WhenCallerNativeBalanceIsInsufficient() external {
        vm.prank(makeAddr("broke"));
        (bool ok, string memory reason) = module.validate(NATIVE, DEFAULT_AMOUNT, "");
        assertFalse(ok);
        assertEq(reason, "Insufficient balance");
    }

    function test_Validate_WhenAllChecksPass() external {
        vm.prank(paymentRails);
        (bool ok, string memory reason) = module.validate(NATIVE, DEFAULT_AMOUNT, "");
        assertTrue(ok);
        assertEq(reason, "");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                ESTIMATE OUTPUT
    //////////////////////////////////////////////////////////////////////////*/

    function test_EstimateOutput() external view {
        (uint256 estimated, address outputToken) = module.estimateOutput(NATIVE, DEFAULT_AMOUNT, "");
        assertEq(estimated, DEFAULT_AMOUNT);
        assertEq(outputToken, address(weth));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  MODULE TYPE
    //////////////////////////////////////////////////////////////////////////*/

    function test_ModuleType() external view {
        assertEq(module.moduleType(), "WRAP");
        assertTrue(module.supportsNativeInput());
    }
}
