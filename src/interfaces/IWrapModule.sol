// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IActionModule } from "./IActionModule.sol";
import { INativeActionModule } from "./INativeActionModule.sol";

/// @title IWrapModule
/// @notice Interface for the module that wraps native value into the chain's wrapped-native token.
/// @dev Takes native value from PaymentRails through {INativeActionModule.executeNative}, deposits it into
/// {wrappedNative}, and returns the wrapped balance to PaymentRails, where it is routed like any other token.
interface IWrapModule is IActionModule, INativeActionModule {
    /// @notice Emitted when native value is wrapped for a PaymentRails.
    /// @dev The module is shared and emits for any caller; `paymentRails` is `msg.sender`, so consumers must filter
    /// on it. The rail's own {IPaymentRails.ActionExecuted} is the authoritative record.
    /// @param paymentRails The PaymentRails that receives the wrapped balance.
    /// @param amount The native value wrapped, in wei.
    event Wrapped(address indexed paymentRails, uint256 amount);

    /// @notice Returns the wrapped-native token this module deposits into, e.g. WETH or WAVAX.
    /// @return The wrapped-native token address.
    function wrappedNative() external view returns (address);
}
