// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title Constants
/// @notice Shared constants for the PaymentRails system.
library Constants {
    /// @notice Sentinel used as the token key for the chain's native value (ETH, AVAX) in PaymentRails.
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
}
