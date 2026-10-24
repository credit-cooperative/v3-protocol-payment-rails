// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IWETH9
/// @notice Minimal interface of the canonical wrapped-native token (WETH9 and its forks such as WAVAX).
interface IWETH9 is IERC20 {
    /// @notice Wraps the native value sent with the call, crediting the caller 1:1.
    function deposit() external payable;

    /// @notice Unwraps `amount` of the token back to native value, sent to the caller.
    /// @param amount The amount to unwrap, in wei.
    function withdraw(uint256 amount) external;
}
