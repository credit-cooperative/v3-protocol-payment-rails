// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IActionModule } from "./IActionModule.sol";
import { INativeActionModule } from "./INativeActionModule.sol";
import { DataTypes } from "../types/DataTypes.sol";

/// @title INativeForwardModule
/// @notice Interface for the module that pays a configured recipient in native value.
/// @dev Takes native value from PaymentRails through {INativeActionModule.executeNative} and forwards it to the
/// recipient in {DataTypes.ForwardParams}. Reverts if the recipient refuses, which PaymentRails reports as a
/// failed action with the value rolled back. {IActionModule.validate} cannot tell whether a recipient will accept
/// value, so a refusing recipient only surfaces at execution.
interface INativeForwardModule is IActionModule, INativeActionModule {
    /// @notice Emitted when native value is paid to a recipient.
    /// @dev The module is shared and emits for any caller; `paymentRails` is `msg.sender`, so consumers must filter
    /// on it. The rail's own {IPaymentRails.ActionExecuted} is the authoritative record.
    /// @param paymentRails The PaymentRails whose value was forwarded.
    /// @param recipient The address that received the native value.
    /// @param amount The native value sent, in wei.
    event NativeForwarded(address indexed paymentRails, address indexed recipient, uint256 amount);

    /// @notice ABI-encodes a {DataTypes.ForwardParams} struct into bytes for {IPaymentRails.configureToken}.
    /// @param params Forward parameters to encode.
    /// @return ABI-encoded bytes representation.
    function encodeParams(DataTypes.ForwardParams calldata params) external pure returns (bytes memory);

    /// @notice Decodes ABI-encoded bytes into a {DataTypes.ForwardParams} struct.
    /// @dev Reverts if the bytes are not valid ABI-encoded `(address, uint256)`.
    /// @param encoded ABI-encoded parameter bytes.
    /// @return params Decoded ForwardParams struct.
    function decodeParams(bytes calldata encoded) external pure returns (DataTypes.ForwardParams memory params);
}
