// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { DataTypes } from "../types/DataTypes.sol";

/// @title IPaymentRails
/// @notice Interface for the core PaymentRails contract that routes tokens through action modules.
/// @dev PaymentRails is a configurable router: it holds tokens, maintains per-token configurations, and
/// delegates execution to pluggable {IActionModule} implementations (forward, swap, bridge, etc.).
///
/// The system uses a dual-permission model:
/// - Configuration ({configureToken}): owner-only.
/// - Execution ({executeAction}): permissionless — anyone can trigger pre-configured actions.
///
/// Safety mechanisms include minimum-balance thresholds, enable/disable flags, module validation,
/// and reentrancy protection.
///
/// Native value is a token like any other: non-zero value is accepted by `receive` and routed under the
/// {NATIVE_TOKEN} key through modules that implement {INativeActionModule}, which are called with the value
/// attached instead of being approved. One configured route per key keeps every destination exclusive.
/// A module returning native to the rail (e.g. an unwrap) uses {returnNative}, which is not logged as a receipt.
interface IPaymentRails {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a token is configured or reconfigured
    /// @dev Emitted by configureToken() after successful configuration
    /// @param token The token address that was configured
    /// @param actionType The action type string (e.g., "FORWARD", "SWAP")
    /// @param actionModule The module contract address
    event TokenConfigured(address indexed token, string actionType, address actionModule);

    /// @notice Emitted when an action is successfully executed
    /// @dev Emitted by executeAction() after module returns success=true
    /// @dev Includes executor address for tracking who triggered the action
    /// @param token The input token address
    /// @param actionType The action type that was executed
    /// @param amountIn The input amount processed
    /// @param amountOut The actual output amount received
    /// @param outputToken The output token address (may differ from input for swaps)
    /// @param executor The address that called executeAction() (keeper, user, etc.)
    event ActionExecuted(
        address indexed token,
        string actionType,
        uint256 amountIn,
        uint256 amountOut,
        address outputToken,
        address indexed executor
    );

    /// @notice Emitted when a module execution fails without reverting the transaction.
    ///
    /// @dev Covers both soft failures (module returns success=false) and hard reverts (module call
    /// reverts).
    ///
    /// @param token The input token address
    /// @param actionType The action type that was attempted
    /// @param amount The input amount that was attempted
    /// @param reason The module's failure reason, or a generic message on revert
    /// @param executor The address that called executeAction()
    event ActionFailed(
        address indexed token, string actionType, uint256 amount, string reason, address indexed executor
    );

    /// @notice Emitted when native value is received through `receive`, i.e. a payer receipt.
    /// @dev Value returned by a module through {returnNative} emits {NativeReturned} instead, so summing this
    /// event gives payer income only.
    /// @param sender The address that sent the value.
    /// @param amount The value received, in wei.
    event NativeReceived(address indexed sender, uint256 amount);

    /// @notice Emitted when a module returns native value through {returnNative}, e.g. after an unwrap.
    /// @param sourceToken The token key whose configured module returned the value.
    /// @param module The module that returned it.
    /// @param amount The value returned, in wei.
    event NativeReturned(address indexed sourceToken, address indexed module, uint256 amount);

    /// @notice Emitted alongside {ActionFailed} when a native module reverts, carrying its revert data.
    /// @dev Reverting is a native module's designed failure channel, so the cause is preserved here.
    /// @param module The native module that reverted.
    /// @param revertData The raw revert data (custom error or reason string).
    event NativeActionReverted(address indexed module, bytes revertData);

    /*//////////////////////////////////////////////////////////////////////////
                                  CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Configure a token's action module and parameters.
    /// @dev Emits a {TokenConfigured} event. Can be called multiple times to reconfigure a token.
    ///
    /// Notes:
    /// - Setting `actionType` to an empty string clears the configuration.
    /// - When clearing, `actionModule` must be `address(0)`.
    /// - Module is validated by calling {IActionModule.moduleType}, which must return a non-empty string.
    ///
    /// Requirements:
    /// - The caller must be the contract owner.
    /// - `token` must not be `address(0)`.
    /// - If `actionType` is non-empty, `actionModule` must implement {IActionModule}.
    /// - If `actionType` is empty, `actionModule` must be `address(0)`.
    /// - If `token` is {NATIVE_TOKEN}, `actionModule` must also report {INativeActionModule.supportsNativeInput}.
    ///
    /// @param token Token address to configure, or {NATIVE_TOKEN} for the native balance.
    /// @param actionType Action identifier (e.g., "FORWARD", "SWAP", "BRIDGE"). Empty string clears config.
    /// @param actionModule Address of the module contract.
    /// @param minBalance Minimum balance threshold for execution.
    /// @param moduleParams ABI-encoded module-specific parameters.
    /// @param enabled Whether the token action should be enabled.
    function configureToken(
        address token,
        string calldata actionType,
        address actionModule,
        uint256 minBalance,
        bytes calldata moduleParams,
        bool enabled
    )
        external;

    /*//////////////////////////////////////////////////////////////////////////
                                   EXECUTION
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Execute the configured action for a token.
    /// @dev Permissionless. Validates preconditions, approves the module for `amount` (or, for {NATIVE_TOKEN},
    /// calls {INativeActionModule.executeNative} with the value attached), and emits {ActionExecuted} on success
    /// or {ActionFailed} on failure. Revokes approval on all ERC-20 paths.
    ///
    /// All execution parameters come from the owner-configured `moduleParams` — the caller supplies
    /// only `(token, amount)`. This eliminates caller-controlled attack surfaces at the architecture
    /// level.
    ///
    /// Notes:
    /// - The executor's address (`msg.sender`) is recorded in both {ActionExecuted} and {ActionFailed}.
    /// - Module execution failures return `false` instead of reverting.
    /// - For {NATIVE_TOKEN} the module is called with the value attached; a native module that fails reverts,
    ///   which rolls the value back and is reported as {ActionFailed}. A native module returning `false` is a
    ///   hard revert, so value can never remain in a module.
    ///
    /// Requirements:
    /// - Token must be configured and enabled.
    /// - `amount` must be > 0 and >= `minBalance`.
    /// - PaymentRails must hold at least `amount` of `token`.
    ///
    /// @param token Token address to execute the action for.
    /// @param amount Amount to process.
    /// @return success True if the module execution succeeded.
    function executeAction(address token, uint256 amount) external returns (bool success);

    /*//////////////////////////////////////////////////////////////////////////
                                NATIVE DEPOSIT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Lets the module configured for `sourceToken` hand native value back to the rail.
    /// @dev Emits a {NativeReturned} event rather than a payer receipt. Used by modules such as an unwrap; the
    /// value is then routed under {NATIVE_TOKEN} like any other.
    ///
    /// Requirements:
    /// - The caller must be the module configured for `sourceToken`.
    /// - `msg.value` must be greater than zero.
    ///
    /// @param sourceToken The token key the calling module is configured for.
    function returnNative(address sourceToken) external payable;

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the sentinel used as the token key for the native balance.
    /// @return The native token sentinel address.
    function NATIVE_TOKEN() external pure returns (address);

    /// @notice Returns the full configuration for a token.
    /// @dev Returns a zero-initialized struct if the token is not configured.
    /// @param token Token address to query.
    /// @return config Complete token configuration struct.
    function getTokenConfig(address token) external view returns (DataTypes.TokenConfig memory config);

    /// @notice Returns the current token balance held by this PaymentRails contract.
    /// @dev For {NATIVE_TOKEN}, returns the native balance.
    /// @param token Token address to check.
    /// @return balance Current balance of the token.
    function getTokenBalance(address token) external view returns (uint256 balance);

    /// @notice Preview the execution outcome for a token action.
    /// @dev Validates all requirements and calls {IActionModule.validate} and {IActionModule.estimateOutput}.
    /// Reverts with specific errors if execution would fail.
    ///
    /// @param token Token address to preview.
    /// @return estimatedOutput Estimated output amount.
    /// @return outputToken Address of the output token.
    function previewExecution(address token) external view returns (uint256 estimatedOutput, address outputToken);
}
