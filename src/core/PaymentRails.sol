// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IPaymentRails } from "../interfaces/IPaymentRails.sol";
import { IActionModule } from "../interfaces/IActionModule.sol";
import { DataTypes } from "../types/DataTypes.sol";
import { Errors } from "../libraries/Errors.sol";
import { IWETH9 } from "../interfaces/IWETH9.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title PaymentRails
/// @author Credit Cooperative
/// @notice See the documentation in {IPaymentRails}.
contract PaymentRails is IPaymentRails, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentRails
    address public immutable wrappedNative;

    /// @dev Maps token addresses to their action configurations
    mapping(address token => DataTypes.TokenConfig config) internal _tokenConfigs;

    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Constructs the PaymentRails contract
    /// @dev Initializes Ownable with the provided owner address
    /// @param initialOwner The address that will own the contract and can configure tokens
    /// @param wrappedNative_ The chain's wrapped-native token, or address(0) to disable native ingress
    constructor(address initialOwner, address wrappedNative_) Ownable(initialOwner) {
        // Check: Wrapped-native is a contract when set (zero disables native ingress)
        if (wrappedNative_ != address(0) && wrappedNative_.code.length == 0) {
            revert Errors.PaymentRails_WrappedNativeNotContract(wrappedNative_);
        }

        wrappedNative = wrappedNative_;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NATIVE INGRESS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Event-only so it fits the 2300-gas stipend of transfer/send; wrapping is deferred to {wrapNative}.
    /// Zero value is rejected so every {NativeReceived} corresponds to a balance increase, and the wrapper's
    /// payout during {sweepNative} is not logged as a receipt.
    receive() external payable {
        // Check: Native ingress enabled
        if (wrappedNative == address(0)) {
            revert Errors.PaymentRails_NativeNotSupported();
        }

        // Check: Non-zero value
        if (msg.value == 0) {
            revert Errors.PaymentRails_ZeroAmount();
        }

        // Log: Receipts only; the wrapper paying out an unwrap is internal movement
        if (msg.sender != wrappedNative) {
            emit NativeReceived(msg.sender, msg.value);
        }
    }

    /// @inheritdoc IPaymentRails
    /// @dev Emits a {NativeWrapped} event.
    function wrapNative() external nonReentrant returns (uint256 amount) {
        // Check: Native ingress enabled
        if (wrappedNative == address(0)) {
            revert Errors.PaymentRails_NativeNotSupported();
        }

        // Check: Non-zero native balance
        amount = address(this).balance;
        if (amount == 0) {
            revert Errors.PaymentRails_ZeroNativeBalance();
        }

        // Interaction: Wrap the full balance
        uint256 balanceBefore = IERC20(wrappedNative).balanceOf(address(this));
        IWETH9(wrappedNative).deposit{ value: amount }();

        // Check: Wrapper credited the exact amount
        uint256 credited = IERC20(wrappedNative).balanceOf(address(this)) - balanceBefore;
        if (credited != amount) {
            revert Errors.PaymentRails_WrapAmountMismatch(amount, credited);
        }

        // Log: Emit wrap event
        emit NativeWrapped(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  NATIVE EXIT
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentRails
    /// @dev Emits a {NativeSwept} event.
    function sweepNative(address recipient) external onlyOwner nonReentrant returns (uint256 amount) {
        // Check: Recipient set
        if (recipient == address(0)) {
            revert Errors.PaymentRails_ZeroRecipient();
        }

        // Interaction: Unwrap the whole wrapped balance; the wrapper pays this contract through receive()
        if (wrappedNative != address(0)) {
            uint256 wrapped = IERC20(wrappedNative).balanceOf(address(this));
            if (wrapped > 0) {
                uint256 nativeBefore = address(this).balance;
                IWETH9(wrappedNative).withdraw(wrapped);

                // Check: Wrapper paid the exact amount
                uint256 received = address(this).balance - nativeBefore;
                if (received != wrapped) {
                    revert Errors.PaymentRails_UnwrapAmountMismatch(wrapped, received);
                }
            }
        }

        // Check: Something to sweep
        amount = address(this).balance;
        if (amount == 0) {
            revert Errors.PaymentRails_ZeroNativeBalance();
        }

        // Interaction: Pay the recipient
        (bool sent,) = recipient.call{ value: amount }("");
        if (!sent) {
            revert Errors.PaymentRails_NativeTransferFailed(recipient);
        }

        // Log: Emit sweep event
        emit NativeSwept(recipient, amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            OWNERSHIP OVERRIDES
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Disables renounceOwnership() to prevent permanently locking the contract configuration.
    function renounceOwnership() public pure override {
        revert Errors.PaymentRails_OwnershipCannotBeRenounced();
    }

    /*//////////////////////////////////////////////////////////////////////////
                        USER-FACING CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentRails
    function getTokenConfig(address token) external view returns (DataTypes.TokenConfig memory) {
        return _tokenConfigs[token];
    }

    /// @inheritdoc IPaymentRails
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc IPaymentRails
    function previewExecution(address token) external view returns (uint256 estimatedOutput, address outputToken) {
        // Check: Token address not zero
        if (token == address(0)) {
            revert Errors.PaymentRails_ZeroTokenAddress();
        }

        // Use storage pointer for gas efficiency (no memory copy needed)
        DataTypes.TokenConfig storage config = _tokenConfigs[token];

        // Check: Action configured
        if (bytes(config.actionType).length == 0) {
            revert Errors.PaymentRails_NoActionConfigured();
        }

        // Check: Token enabled
        if (!config.enabled) {
            revert Errors.PaymentRails_TokenNotEnabled();
        }

        // Check: Module is a contract
        if (config.actionModule.code.length == 0) {
            revert Errors.PaymentRails_InvalidModule();
        }

        // Check: Get token balance
        // Note: Assumes token is trusted ERC20 implementation
        // Malicious tokens could return fake balance or revert, but this is acceptable for preview
        uint256 balance = IERC20(token).balanceOf(address(this));

        // Check: Native waiting for wrapNative() is the actionable reason when wrapping would make the balance
        // sufficient
        _checkNativePendingWrap(token, balance, config.minBalance);

        // Check: Non-zero balance (consistency with executeAction which checks amount != 0)
        if (balance == 0) {
            revert Errors.PaymentRails_ZeroAmount();
        }

        // Check: Balance meets minimum threshold
        if (balance < config.minBalance) {
            revert Errors.PaymentRails_BelowMinimumBalance(balance, config.minBalance);
        }

        // Check: Module validation
        (bool isValid, string memory reason) =
            IActionModule(config.actionModule).validate(token, balance, config.moduleParams);
        if (!isValid) {
            // Module validation failed - revert with module's reason
            // Note: Cannot revert with module's custom error, so we use a descriptive revert
            revert(reason);
        }

        // All checks passed - get output estimation
        return IActionModule(config.actionModule).estimateOutput(token, balance, config.moduleParams);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Reverts with the pending native amount when `token` is the wrapper, its balance is short of `minBalance`
    /// (or zero), and wrapping the waiting native would make it sufficient, so a keeper learns to wrap first.
    function _checkNativePendingWrap(address token, uint256 balance, uint256 minBalance) private view {
        if (token != wrappedNative) {
            return;
        }
        uint256 pending = address(this).balance;
        if (pending == 0) {
            return;
        }
        bool short = balance == 0 || balance < minBalance;
        if (short && balance + pending >= minBalance) {
            revert Errors.PaymentRails_NativePendingWrap(pending);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                    USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentRails
    /// @dev Emits a {TokenConfigured} event.
    function configureToken(
        address token,
        string calldata actionType,
        address actionModule,
        uint256 minBalance,
        bytes calldata moduleParams,
        bool enabled
    )
        external
        onlyOwner
    {
        // Check: Token address not zero
        if (token == address(0)) {
            revert Errors.PaymentRails_ZeroTokenAddress();
        }

        // Empty string means clearing configuration
        bool isNoneAction = bytes(actionType).length == 0;

        if (isNoneAction) {
            // Check: When clearing config, module should be zero address
            if (actionModule != address(0)) {
                revert Errors.PaymentRails_NoneActionRequiresZeroModule();
            }
        } else {
            // Check: Action module not zero address
            if (actionModule == address(0)) {
                revert Errors.PaymentRails_ZeroModuleAddress();
            }

            // Check: Validate module implements IActionModule correctly
            try IActionModule(actionModule).moduleType() returns (string memory moduleTypeStr) {
                // Check: Module returns valid type string
                if (bytes(moduleTypeStr).length == 0) {
                    revert Errors.PaymentRails_InvalidModule();
                }
            } catch {
                revert Errors.PaymentRails_ModuleValidationFailed();
            }
        }

        // Effect: Store configuration
        _tokenConfigs[token] = DataTypes.TokenConfig({
            actionType: actionType,
            actionModule: actionModule,
            enabled: enabled,
            minBalance: minBalance,
            moduleParams: moduleParams
        });

        // Log: Emit configuration event
        emit TokenConfigured(token, actionType, actionModule);
    }

    /// @inheritdoc IPaymentRails
    /// @dev Emits {ActionExecuted} on success, {ActionFailed} on failure.
    function executeAction(address token, uint256 amount) external nonReentrant returns (bool success) {
        DataTypes.TokenConfig memory config = _tokenConfigs[token];

        if (!config.enabled) {
            revert Errors.PaymentRails_TokenNotEnabled();
        }
        if (bytes(config.actionType).length == 0) {
            revert Errors.PaymentRails_NoActionConfigured();
        }
        if (amount == 0) {
            revert Errors.PaymentRails_ZeroAmount();
        }
        if (amount < config.minBalance) {
            revert Errors.PaymentRails_BelowMinimumBalance(amount, config.minBalance);
        }

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) {
            revert Errors.PaymentRails_InsufficientBalance(balance, amount);
        }

        IERC20(token).forceApprove(config.actionModule, amount);

        try IActionModule(config.actionModule).execute(token, amount, config.moduleParams) returns (
            DataTypes.ExecutionResult memory result
        ) {
            if (result.success) {
                IERC20(token).forceApprove(config.actionModule, 0);
                emit ActionExecuted(token, config.actionType, amount, result.amountOut, result.outputToken, msg.sender);
                return true;
            } else {
                IERC20(token).forceApprove(config.actionModule, 0);
                emit ActionFailed(token, config.actionType, amount, result.failureReason, msg.sender);
                return false;
            }
        } catch {
            IERC20(token).forceApprove(config.actionModule, 0);
            emit ActionFailed(token, config.actionType, amount, "Module execution reverted", msg.sender);
            return false;
        }
    }
}
