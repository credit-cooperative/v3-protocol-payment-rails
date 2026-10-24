// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { NativeForwardModuleBase } from "./NativeForwardModuleBase.t.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { RejectingRecipient, StipendSender } from "../../../../shared/mocks/NativeMocks.sol";

/// @dev Params are always built before any cheatcode: encodeParams is an external call and would consume a
///      prank or an expected revert.
contract NativeForwardModuleTest is NativeForwardModuleBase {
    /*//////////////////////////////////////////////////////////////////////////
                                 EXECUTE NATIVE
    //////////////////////////////////////////////////////////////////////////*/

    function test_ExecuteNative_RevertWhen_AmountIsZero() external {
        bytes memory params = _params(recipient, 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NativeForwardModule_ValueMismatch.selector, 0, 0));
        vm.prank(paymentRails);
        module.executeNative{ value: 0 }(0, params);
    }

    function test_ExecuteNative_RevertWhen_ValueDiffersFromAmount() external {
        bytes memory params = _params(recipient, 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NativeForwardModule_ValueMismatch.selector, DEFAULT_AMOUNT, 1));
        vm.prank(paymentRails);
        module.executeNative{ value: 1 }(DEFAULT_AMOUNT, params);
    }

    function test_ExecuteNative_RevertWhen_RecipientIsZeroAddress() external {
        bytes memory params = _params(address(0), 0);
        vm.expectRevert(Errors.NativeForwardModule_ZeroRecipient.selector);
        vm.prank(paymentRails);
        module.executeNative{ value: DEFAULT_AMOUNT }(DEFAULT_AMOUNT, params);
    }

    function test_ExecuteNative_RevertWhen_AmountIsBelowMinAmount() external {
        uint256 amount = DEFAULT_MIN_AMOUNT - 1;
        bytes memory params = _params(recipient, DEFAULT_MIN_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NativeForwardModule_AmountBelowMinimum.selector, amount, DEFAULT_MIN_AMOUNT)
        );
        vm.prank(paymentRails);
        module.executeNative{ value: amount }(amount, params);
    }

    function test_ExecuteNative_RevertWhen_RecipientRefusesTheValue() external {
        RejectingRecipient rejecting = new RejectingRecipient();
        bytes memory params = _params(address(rejecting), 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NativeForwardModule_TransferFailed.selector, address(rejecting)));
        vm.prank(paymentRails);
        module.executeNative{ value: DEFAULT_AMOUNT }(DEFAULT_AMOUNT, params);
    }

    function test_ExecuteNative_WhenRecipientAccepts() external {
        bytes memory params = _params(recipient, DEFAULT_MIN_AMOUNT);

        vm.expectEmit(true, true, false, true, address(module));
        emit NativeForwarded(paymentRails, recipient, DEFAULT_AMOUNT);

        vm.prank(paymentRails);
        DataTypes.ExecutionResult memory result = module.executeNative{ value: DEFAULT_AMOUNT }(DEFAULT_AMOUNT, params);

        assertTrue(result.success, "success");
        assertEq(result.amountOut, DEFAULT_AMOUNT, "amountOut");
        assertEq(result.outputToken, NATIVE, "outputToken");
        assertEq(abi.decode(result.data, (address)), recipient, "data");
        assertEq(recipient.balance, DEFAULT_AMOUNT, "recipient balance");
        assertEq(address(module).balance, 0, "module native");
    }

    function test_ExecuteNative_WhenRecipientIsAContract() external {
        StipendSender contractRecipient = new StipendSender();
        bytes memory params = _params(address(contractRecipient), 0);

        vm.prank(paymentRails);
        module.executeNative{ value: DEFAULT_AMOUNT }(DEFAULT_AMOUNT, params);

        assertEq(address(contractRecipient).balance, DEFAULT_AMOUNT);
    }

    function testFuzz_ExecuteNative_WhenAmountIsAtOrAboveMinAmount(uint256 amount) external {
        amount = bound(amount, DEFAULT_MIN_AMOUNT, 1_000_000 ether);
        vm.deal(paymentRails, amount);
        bytes memory params = _params(recipient, DEFAULT_MIN_AMOUNT);

        vm.prank(paymentRails);
        module.executeNative{ value: amount }(amount, params);

        assertEq(recipient.balance, amount);
        assertEq(address(module).balance, 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    EXECUTE
    //////////////////////////////////////////////////////////////////////////*/

    function test_Execute_ShouldReturnAFailedResult() external {
        bytes memory params = _params(recipient, 0);
        vm.prank(paymentRails);
        DataTypes.ExecutionResult memory result = module.execute(address(token), DEFAULT_AMOUNT, params);
        assertFalse(result.success);
        assertEq(result.failureReason, "Native input only");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    VALIDATE
    //////////////////////////////////////////////////////////////////////////*/

    function test_Validate_WhenTokenIsNotTheNativeSentinel() external {
        bytes memory params = _params(recipient, 0);
        vm.prank(paymentRails);
        (bool ok, string memory reason) = module.validate(address(token), DEFAULT_AMOUNT, params);
        assertFalse(ok);
        assertEq(reason, "Native input only");
    }

    function test_Validate_WhenTokenIsNotTheNativeSentinel_MalformedParamsDoNotRevert() external {
        vm.prank(paymentRails);
        (bool ok, string memory reason) = module.validate(address(token), DEFAULT_AMOUNT, hex"");
        assertFalse(ok);
        assertEq(reason, "Native input only");
    }

    function test_Validate_WhenAmountIsZero() external {
        bytes memory params = _params(recipient, 0);
        vm.prank(paymentRails);
        (bool ok, string memory reason) = module.validate(NATIVE, 0, params);
        assertFalse(ok);
        assertEq(reason, "Zero amount");
    }

    function test_Validate_WhenRecipientIsZeroAddress() external {
        bytes memory params = _params(address(0), 0);
        vm.prank(paymentRails);
        (bool ok, string memory reason) = module.validate(NATIVE, DEFAULT_AMOUNT, params);
        assertFalse(ok);
        assertEq(reason, "Zero recipient address");
    }

    function test_Validate_WhenAmountIsBelowMinAmount() external {
        bytes memory params = _params(recipient, DEFAULT_MIN_AMOUNT);
        vm.prank(paymentRails);
        (bool ok, string memory reason) = module.validate(NATIVE, DEFAULT_MIN_AMOUNT - 1, params);
        assertFalse(ok);
        assertEq(reason, "Amount below minimum");
    }

    function test_Validate_WhenCallerNativeBalanceIsInsufficient() external {
        bytes memory params = _params(recipient, 0);
        vm.prank(makeAddr("broke"));
        (bool ok, string memory reason) = module.validate(NATIVE, DEFAULT_AMOUNT, params);
        assertFalse(ok);
        assertEq(reason, "Insufficient balance");
    }

    function test_Validate_WhenAllChecksPass() external {
        bytes memory params = _params(recipient, DEFAULT_MIN_AMOUNT);
        vm.prank(paymentRails);
        (bool ok, string memory reason) = module.validate(NATIVE, DEFAULT_AMOUNT, params);
        assertTrue(ok);
        assertEq(reason, "");
    }

    /*//////////////////////////////////////////////////////////////////////////
                    ESTIMATE OUTPUT / MODULE TYPE / PARAMS
    //////////////////////////////////////////////////////////////////////////*/

    function test_EstimateOutput() external view {
        (uint256 estimated, address outputToken) = module.estimateOutput(NATIVE, DEFAULT_AMOUNT, "");
        assertEq(estimated, DEFAULT_AMOUNT);
        assertEq(outputToken, NATIVE);
    }

    function test_ModuleType() external view {
        assertEq(module.moduleType(), "NATIVE_FORWARD");
        assertTrue(module.supportsNativeInput());
    }

    function test_EncodeDecodeParams_ShouldRoundtrip() external view {
        DataTypes.ForwardParams memory decoded = module.decodeParams(_params(recipient, DEFAULT_MIN_AMOUNT));
        assertEq(decoded.recipient, recipient);
        assertEq(decoded.minAmount, DEFAULT_MIN_AMOUNT);
    }

    function test_EncodeDecodeParams_RevertOnEmptyBytes() external {
        vm.expectRevert();
        module.decodeParams("");
    }

    function testFuzz_EncodeDecodeParams_ShouldRoundtripAnyValues(address to, uint256 minAmount) external view {
        DataTypes.ForwardParams memory decoded = module.decodeParams(_params(to, minAmount));
        assertEq(decoded.recipient, to);
        assertEq(decoded.minAmount, minAmount);
    }
}
