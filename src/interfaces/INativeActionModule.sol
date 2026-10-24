// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { DataTypes } from "../types/DataTypes.sol";

/// @title INativeActionModule
/// @notice Interface for modules that act on native value pushed to them by PaymentRails.
/// @dev PaymentRails routes its native balance under the {Constants.NATIVE_TOKEN} key: instead of approving a
/// module, it calls {executeNative} with the value attached. Because the value has already left PaymentRails
/// when the module runs, a native module MUST revert on failure; only a revert rolls the value back.
/// PaymentRails reports such a revert as {IPaymentRails.ActionFailed}, and treats a `false` result as a hard
/// error so value can never remain in a module.
interface INativeActionModule {
    /// @notice Executes the module's action on the native value sent with the call.
    /// @dev `msg.value` equals `amount`. Reverts on any failure.
    /// @param amount The native value to process, in wei.
    /// @param params Module-specific parameters (ABI-encoded via the module's `encodeParams`, if any).
    /// @return result Execution result with success status and output details.
    function executeNative(
        uint256 amount,
        bytes calldata params
    )
        external
        payable
        returns (DataTypes.ExecutionResult memory result);

    /// @notice Returns true for modules that take native value through {executeNative}.
    /// @dev Probed by {IPaymentRails.configureToken} when the token key is {Constants.NATIVE_TOKEN}.
    /// @return True if the module accepts native input.
    function supportsNativeInput() external view returns (bool);
}
