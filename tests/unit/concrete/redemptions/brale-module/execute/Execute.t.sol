// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Vm } from "forge-std/src/Vm.sol";
import { BraleModuleBase } from "../BraleModuleBase.t.sol";
import { DataTypes } from "../../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";
import { MockERC20 } from "../../../../../shared/mocks/MockERC20.sol";
import { MockPaymentRails } from "../../../../../shared/mocks/MockPaymentRails.sol";
import { FailingTransferERC20 } from "../../../../../shared/mocks/FailingTransferERC20.sol";
import { RevertingTransferERC20 } from "../../../../../shared/mocks/RevertingTransferERC20.sol";
import { FeeOnTransferERC20 } from "../../../../../shared/mocks/FeeOnTransferERC20.sol";
import { SenderFeeERC20 } from "../../../../../shared/mocks/SenderFeeERC20.sol";

/// @dev Token whose transferFrom tries to re-enter the module through the rails once.
contract ReentrantBraleToken is MockERC20 {
    MockPaymentRails internal rails;
    bytes internal reenterParams;
    bool internal entered;

    constructor() MockERC20("Reentrant", "RE") { }

    function arm(MockPaymentRails _rails, bytes memory _params) external {
        rails = _rails;
        reenterParams = _params;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (!entered) {
            entered = true;
            rails.initiateSwap(address(this), amount, reenterParams);
        }
        return super.transferFrom(from, to, amount);
    }
}

contract BraleModule_Execute_Test is BraleModuleBase {
    function _assertFailed(DataTypes.ExecutionResult memory r, string memory reason) internal view {
        assertFalse(r.success);
        assertEq(r.failureReason, reason);
        assertEq(r.amountOut, 0);
        assertEq(r.outputToken, address(token));
    }

    function _assertNoModuleLogs() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].emitter != address(module), "module must not emit");
        }
    }

    function _assertNoEffects() internal view {
        assertEq(module.redemptionNonce(), 0);
        assertEq(token.balanceOf(depositAddress), 0);
        assertEq(token.balanceOf(address(paymentRails)), RAILS_BALANCE);
        assertEq(token.balanceOf(address(module)), 0);
    }

    function _invalid(uint256 amount, bytes memory params, string memory reason) internal {
        vm.recordLogs();
        DataTypes.ExecutionResult memory r = paymentRails.initiateSwap(address(token), amount, params);
        _assertFailed(r, reason);
        _assertNoModuleLogs();
        _assertNoEffects();
    }

    function test_RevertWhen_CallerIsNotPaymentRails() external {
        bytes memory params = _params();
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Errors.BraleModule_NotPaymentRails.selector, attacker, paymentRails));
        module.execute(address(token), 1e18, params);
    }

    function test_WhenAmountIsZero_ReturnsFailed() external {
        _invalid(0, _params(), "Zero amount");
    }

    function test_WhenParamsAreOldTwoFieldEncoding_ReturnsFailed() external {
        _invalid(1e18, abi.encode(depositAddress, address(usdc)), "Invalid params encoding");
    }

    function test_WhenMinAmountIsZero_ReturnsFailed() external {
        _invalid(1e18, _params(depositAddress, address(usdc), 0), "Zero minimum amount");
    }

    function test_WhenAmountBelowMinAmount_ReturnsFailed() external {
        _invalid(1e18 - 1, _params(depositAddress, address(usdc), 1e18), "Below minimum redemption");
    }

    function test_WhenAmountEqualsMinAmount_Succeeds() external {
        DataTypes.ExecutionResult memory r =
            paymentRails.initiateSwap(address(token), 1e18, _params(depositAddress, address(usdc), 1e18));
        assertTrue(r.success);
        assertEq(module.redemptionNonce(), 1);
        assertEq(token.balanceOf(depositAddress), 1e18);
    }

    function test_WhenParamsTooShort_ReturnsFailed() external {
        _invalid(1e18, hex"1234", "Invalid params encoding");
    }

    function test_WhenParamsHaveDirtyBits_ReturnsFailed() external {
        _invalid(1e18, abi.encode(uint256(type(uint160).max) + 1, address(usdc), uint256(1)), "Invalid params encoding");
    }

    function test_WhenDepositAddressIsZero_ReturnsFailed() external {
        _invalid(1e18, _params(address(0), address(usdc)), "Zero deposit address");
    }

    function test_WhenDepositAddressIsPaymentRails_ReturnsFailed() external {
        _invalid(1e18, _params(address(paymentRails), address(usdc)), "Deposit address is PaymentRails");
    }

    function test_WhenDepositAddressIsModule_ReturnsFailed() external {
        _invalid(1e18, _params(address(module), address(usdc)), "Deposit address is module");
    }

    function test_WhenDepositAddressIsInputToken_ReturnsFailed() external {
        _invalid(1e18, _params(address(token), address(usdc)), "Deposit address is input token");
    }

    function test_WhenDepositAddressIsOutputToken_ReturnsFailed() external {
        _invalid(1e18, _params(address(usdc), address(usdc)), "Deposit address is output token");
    }

    function test_WhenOutputTokenIsZero_ReturnsFailed() external {
        _invalid(1e18, _params(depositAddress, address(0)), "Zero output token");
    }

    function test_WhenOutputTokenEqualsInputToken_ReturnsFailed() external {
        _invalid(1e18, _params(depositAddress, address(token)), "Output token equals input token");
    }

    function test_WhenTransferReturnsFalse_ReturnsFailedAndRestoresNonce() external {
        FailingTransferERC20 bad = new FailingTransferERC20();
        bad.mint(address(paymentRails), 10e18);

        vm.recordLogs();
        DataTypes.ExecutionResult memory r = paymentRails.initiateSwap(address(bad), 1e18, _params());
        assertFalse(r.success);
        assertEq(r.failureReason, "Token transfer failed");
        _assertNoModuleLogs();
        assertEq(module.redemptionNonce(), 0);
        assertEq(bad.balanceOf(depositAddress), 0);
    }

    function test_WhenTransferReverts_ReturnsFailedAndRestoresNonce() external {
        RevertingTransferERC20 bad = new RevertingTransferERC20();
        bad.mint(address(paymentRails), 10e18);

        vm.recordLogs();
        DataTypes.ExecutionResult memory r = paymentRails.initiateSwap(address(bad), 1e18, _params());
        assertFalse(r.success);
        assertEq(r.failureReason, "Token transfer failed");
        _assertNoModuleLogs();
        assertEq(module.redemptionNonce(), 0);
    }

    function test_RevertWhen_TokenChargesRecipientFee() external {
        FeeOnTransferERC20 fot = new FeeOnTransferERC20();
        fot.mint(address(paymentRails), 100e18);

        uint256 amount = 10e18;
        uint256 fee = (amount * fot.FEE_BPS()) / 10_000;
        bytes memory params = _params();
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BraleModule_UnexpectedDeliveredAmount.selector, amount, amount - fee)
        );
        paymentRails.initiateSwap(address(fot), amount, params);
    }

    function test_RevertWhen_TokenChargesSenderFee() external {
        SenderFeeERC20 sfee = new SenderFeeERC20();
        sfee.mint(address(paymentRails), 100e18);

        uint256 amount = 10e18;
        uint256 fee = (amount * sfee.FEE_BPS()) / 10_000;
        bytes memory params = _params();
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BraleModule_UnexpectedDebitedAmount.selector, amount, amount + fee)
        );
        paymentRails.initiateSwap(address(sfee), amount, params);
    }

    function test_WhenTokenReenters_ReturnsFailedAndNonceUnchanged() external {
        ReentrantBraleToken re = new ReentrantBraleToken();
        re.mint(address(paymentRails), 10e18);
        re.arm(paymentRails, _params());

        DataTypes.ExecutionResult memory r = paymentRails.initiateSwap(address(re), 1e18, _params());
        assertFalse(r.success);
        assertEq(r.failureReason, "Token transfer failed");
        assertEq(module.redemptionNonce(), 0);
        assertEq(re.balanceOf(depositAddress), 0);
        assertEq(re.balanceOf(address(module)), 0);
    }

    function test_WhenParamsValid_MovesExactAmount() external {
        uint256 amount = 123e18;
        DataTypes.ExecutionResult memory r = _execute(amount);

        assertTrue(r.success);
        assertEq(token.balanceOf(depositAddress), amount);
        assertEq(token.balanceOf(address(paymentRails)), RAILS_BALANCE - amount);
        assertEq(token.balanceOf(address(module)), 0);
    }

    function test_WhenParamsValid_EmitsEventAndIncrementsNonce() external {
        uint256 amount = 5e18;
        vm.expectEmit(true, true, true, true, address(module));
        emit RedemptionInitiated(
            _expectedId(0), address(token), depositAddress, 0, amount, address(paymentRails), address(usdc)
        );
        _execute(amount);
        assertEq(module.redemptionNonce(), 1);
    }

    function test_WhenParamsValid_ReturnsSuccessResult() external {
        DataTypes.ExecutionResult memory r = _execute(5e18);
        assertTrue(r.success);
        assertEq(r.amountOut, 0);
        assertEq(r.outputToken, address(usdc));
        assertEq(r.data, abi.encode(_expectedId(0)));
        assertEq(bytes(r.failureReason).length, 0);
    }

    function test_WhenCalledTwice_ProducesDistinctIds() external {
        DataTypes.ExecutionResult memory r0 = _execute(1e18);
        DataTypes.ExecutionResult memory r1 = _execute(1e18);

        assertEq(r0.data, abi.encode(_expectedId(0)));
        assertEq(r1.data, abi.encode(_expectedId(1)));
        assertTrue(keccak256(r0.data) != keccak256(r1.data));
        assertEq(module.redemptionNonce(), 2);
    }

    function testFuzz_WhenParamsValid_MovesExactAmount(uint256 amount) external {
        amount = bound(amount, 1, RAILS_BALANCE);
        DataTypes.ExecutionResult memory r = _execute(amount);

        assertTrue(r.success);
        assertEq(token.balanceOf(depositAddress), amount);
        assertEq(token.balanceOf(address(paymentRails)), RAILS_BALANCE - amount);
        assertEq(token.balanceOf(address(module)), 0);
    }
}
