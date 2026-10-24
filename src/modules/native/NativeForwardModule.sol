// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { INativeForwardModule } from "../../interfaces/INativeForwardModule.sol";
import { INativeActionModule } from "../../interfaces/INativeActionModule.sol";
import { IActionModule } from "../../interfaces/IActionModule.sol";
import { ActionModuleBase } from "../../abstracts/ActionModuleBase.sol";
import { DataTypes } from "../../types/DataTypes.sol";
import { Constants } from "../../libraries/Constants.sol";
import { Errors } from "../../libraries/Errors.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title NativeForwardModule
/// @author Credit Cooperative
/// @notice See the documentation in {INativeForwardModule}.
contract NativeForwardModule is INativeForwardModule, ActionModuleBase, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////////////////
                        USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc INativeActionModule
    /// @dev Emits a {NativeForwarded} event.
    function executeNative(
        uint256 amount,
        bytes calldata params
    )
        external
        payable
        nonReentrant
        returns (DataTypes.ExecutionResult memory result)
    {
        // Check: Non-zero value matching the requested amount
        if (amount == 0 || msg.value != amount) {
            revert Errors.NativeForwardModule_ValueMismatch(amount, msg.value);
        }

        DataTypes.ForwardParams memory forwardParams = decodeParams(params);

        // Check: Recipient set and amount at or above the minimum
        if (forwardParams.recipient == address(0)) {
            revert Errors.NativeForwardModule_ZeroRecipient();
        }
        if (amount < forwardParams.minAmount) {
            revert Errors.NativeForwardModule_AmountBelowMinimum(amount, forwardParams.minAmount);
        }

        // Interaction: Pay the recipient; a refusal reverts so PaymentRails rolls the value back
        (bool sent,) = forwardParams.recipient.call{ value: amount }("");
        if (!sent) {
            revert Errors.NativeForwardModule_TransferFailed(forwardParams.recipient);
        }

        // Log: Emit forward event
        emit NativeForwarded(msg.sender, forwardParams.recipient, amount);

        return _successResult(amount, Constants.NATIVE_TOKEN, abi.encode(forwardParams.recipient));
    }

    /// @inheritdoc IActionModule
    /// @dev ERC-20 input is not an action of this module; native value arrives through {executeNative}.
    function execute(
        address token,
        uint256, /* amount */
        bytes calldata /* params */
    )
        external
        pure
        override(ActionModuleBase, IActionModule)
        returns (DataTypes.ExecutionResult memory result)
    {
        return _failedResult(token, "Native input only");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        USER-FACING CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IActionModule
    function validate(
        address token,
        uint256 amount,
        bytes calldata params
    )
        external
        view
        override(ActionModuleBase, IActionModule)
        returns (bool isValid, string memory reason)
    {
        if (token != Constants.NATIVE_TOKEN) {
            return (false, "Native input only");
        }

        if (amount == 0) {
            return (false, "Zero amount");
        }

        DataTypes.ForwardParams memory forwardParams = decodeParams(params);

        if (!_isValidAddress(forwardParams.recipient)) {
            return (false, "Zero recipient address");
        }

        if (amount < forwardParams.minAmount) {
            return (false, "Amount below minimum");
        }

        if (msg.sender.balance < amount) {
            return (false, "Insufficient balance");
        }

        return (true, "");
    }

    /// @inheritdoc IActionModule
    function estimateOutput(
        address, /* token */
        uint256 amount,
        bytes calldata /* params */
    )
        external
        pure
        override(ActionModuleBase, IActionModule)
        returns (uint256 estimatedOutput, address outputToken)
    {
        return (amount, Constants.NATIVE_TOKEN);
    }

    /// @inheritdoc IActionModule
    function moduleType() external pure override(ActionModuleBase, IActionModule) returns (string memory) {
        return "NATIVE_FORWARD";
    }

    /// @inheritdoc INativeActionModule
    function supportsNativeInput() external pure returns (bool) {
        return true;
    }

    /*//////////////////////////////////////////////////////////////////////////
                        FORWARD-SPECIFIC FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc INativeForwardModule
    function encodeParams(DataTypes.ForwardParams calldata params) external pure returns (bytes memory) {
        return abi.encode(params.recipient, params.minAmount);
    }

    /// @inheritdoc INativeForwardModule
    function decodeParams(bytes calldata encoded) public pure returns (DataTypes.ForwardParams memory params) {
        (params.recipient, params.minAmount) = abi.decode(encoded, (address, uint256));
    }
}
