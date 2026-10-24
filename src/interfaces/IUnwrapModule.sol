// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IActionModule } from "./IActionModule.sol";

/// @title IUnwrapModule
/// @notice Interface for the module that unwraps the wrapped-native token back into native value.
/// @dev A regular {IActionModule}: pulls {wrappedNative} from PaymentRails, withdraws it, and hands the native
/// value back through {IPaymentRails.returnNative}, so it is not logged as a payer receipt and is then routed
/// under the {Constants.NATIVE_TOKEN} key.
interface IUnwrapModule is IActionModule {
    /// @notice Emitted when wrapped balance is unwrapped for a PaymentRails.
    /// @dev The module is shared and emits for any caller; `paymentRails` is `msg.sender`, so consumers must filter
    /// on it. The rail's own {IPaymentRails.ActionExecuted} is the authoritative record.
    /// @param paymentRails The PaymentRails that receives the native value.
    /// @param amount The value unwrapped, in wei.
    event Unwrapped(address indexed paymentRails, uint256 amount);

    /// @notice Returns the wrapped-native token this module unwraps, e.g. WETH or WAVAX.
    /// @return The wrapped-native token address.
    function wrappedNative() external view returns (address);
}
