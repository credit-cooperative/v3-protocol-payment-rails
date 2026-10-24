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
/// Non-zero native value is accepted by `receive` and converted by {wrapNative} into {wrappedNative}, after
/// which it is routed like any other token. A zero {wrappedNative} disables native ingress. Wrapping is
/// permissionless; the only native egress is the owner-only {sweepNative}, which unwraps the whole wrapped
/// balance (however it arrived) and pays out everything in one call, so a stranger wrapping ahead of it changes
/// nothing. A configured route for {wrappedNative} can still be executed by anyone before the sweep lands.
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

    /// @notice Emitted when native value is received from anyone but the wrapper.
    /// @dev The wrapper's payout during {sweepNative} is internal movement and emits nothing here, so summing
    /// this event gives payer income only.
    /// @param sender The address that sent the value.
    /// @param amount The value received, in wei.
    event NativeReceived(address indexed sender, uint256 amount);

    /// @notice Emitted when the native balance is wrapped into the wrapped-native token.
    /// @param caller The address that triggered the wrap.
    /// @param amount The native value wrapped, in wei.
    event NativeWrapped(address indexed caller, uint256 amount);

    /// @notice Emitted when the owner sweeps the native balance out.
    /// @param recipient The address that received the value.
    /// @param amount The total value sent, including the unwrapped balance, in wei.
    event NativeSwept(address indexed recipient, uint256 amount);

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
    ///
    /// @param token Token address to configure.
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
    /// @dev Permissionless. Validates preconditions, approves the module for `amount`, calls
    /// {IActionModule.execute}, and emits {ActionExecuted} on success or {ActionFailed} on failure.
    /// Revokes approval on all paths.
    ///
    /// All execution parameters come from the owner-configured `moduleParams` — the caller supplies
    /// only `(token, amount)`. This eliminates caller-controlled attack surfaces at the architecture
    /// level.
    ///
    /// Notes:
    /// - The executor's address (`msg.sender`) is recorded in both {ActionExecuted} and {ActionFailed}.
    /// - Module execution failures return `false` instead of reverting.
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
                                NATIVE INGRESS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Wraps the entire native balance into the wrapped-native token.
    /// @dev Permissionless. Emits a {NativeWrapped} event. Also sweeps value that arrived without `receive`.
    ///
    /// Requirements:
    /// - {wrappedNative} must not be `address(0)`.
    /// - The native balance must be greater than zero.
    /// - The wrapper must credit exactly the deposited amount.
    ///
    /// @return amount The native value wrapped, in wei.
    function wrapNative() external returns (uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////
                                  NATIVE EXIT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Unwraps the whole wrapped balance and sends the entire native balance to `recipient`.
    /// @dev Owner-only. Emits a {NativeSwept} event; the wrapper's payout is internal and emits nothing. Works on
    /// rails without a wrapper too, so force-fed value is always recoverable. Reverts if the recipient refuses.
    ///
    /// Requirements:
    /// - The caller must be the contract owner.
    /// - `recipient` must not be `address(0)`.
    /// - The combined native and wrapped balance must be greater than zero.
    /// - The wrapper must pay out exactly the wrapped balance.
    ///
    /// @param recipient The address that receives the value.
    /// @return amount The total native value sent, in wei.
    function sweepNative(address recipient) external returns (uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the wrapped-native token (e.g. WETH, WAVAX); `address(0)` means native ingress is disabled.
    /// @dev When disabled, value that bypasses `receive` can still leave through {sweepNative}.
    /// @return The wrapped-native token address.
    function wrappedNative() external view returns (address);

    /// @notice Returns the full configuration for a token.
    /// @dev Returns a zero-initialized struct if the token is not configured.
    /// @param token Token address to query.
    /// @return config Complete token configuration struct.
    function getTokenConfig(address token) external view returns (DataTypes.TokenConfig memory config);

    /// @notice Returns the current token balance held by this PaymentRails contract.
    /// @param token Token address to check.
    /// @return balance Current balance of the token.
    function getTokenBalance(address token) external view returns (uint256 balance);

    /// @notice Preview the execution outcome for a token action.
    /// @dev Validates all requirements and calls {IActionModule.validate} and {IActionModule.estimateOutput}.
    /// Reverts with specific errors if execution would fail. For {wrappedNative}, reverts with
    /// `PaymentRails_NativePendingWrap` when the wrapped balance is short but native value is waiting for
    /// {wrapNative}, so a keeper learns to wrap first.
    ///
    /// @param token Token address to preview.
    /// @return estimatedOutput Estimated output amount.
    /// @return outputToken Address of the output token.
    function previewExecution(address token) external view returns (uint256 estimatedOutput, address outputToken);
}
