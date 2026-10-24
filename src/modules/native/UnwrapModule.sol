// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IUnwrapModule } from "../../interfaces/IUnwrapModule.sol";
import { IPaymentRails } from "../../interfaces/IPaymentRails.sol";
import { IActionModule } from "../../interfaces/IActionModule.sol";
import { IWETH9 } from "../../interfaces/IWETH9.sol";
import { ActionModuleBase } from "../../abstracts/ActionModuleBase.sol";
import { DataTypes } from "../../types/DataTypes.sol";
import { Constants } from "../../libraries/Constants.sol";
import { Errors } from "../../libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title UnwrapModule
/// @author Credit Cooperative
/// @notice See the documentation in {IUnwrapModule}.
contract UnwrapModule is IUnwrapModule, ActionModuleBase, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUnwrapModule
    address public immutable wrappedNative;

    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param wrappedNative_ The chain's wrapped-native token this module unwraps
    constructor(address wrappedNative_) {
        // Check: Wrapped-native is a contract
        if (wrappedNative_ == address(0)) {
            revert Errors.UnwrapModule_ZeroWrappedNative();
        }
        if (wrappedNative_.code.length == 0) {
            revert Errors.UnwrapModule_WrappedNativeNotContract(wrappedNative_);
        }

        wrappedNative = wrappedNative_;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NATIVE RECEIPT
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Takes the unwrapped value from `withdraw()` only. WETH9 pays it with `transfer`, so this stays
    /// inside the 2300-gas stipend: no event, no storage.
    receive() external payable {
        // Check: Value comes from the wrapper
        if (msg.sender != wrappedNative) {
            revert Errors.UnwrapModule_UnexpectedNativeSender(msg.sender);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                        USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IActionModule
    /// @dev Emits an {Unwrapped} event on success.
    function execute(
        address token,
        uint256 amount,
        bytes calldata /* params */
    )
        external
        override(ActionModuleBase, IActionModule)
        nonReentrant
        returns (DataTypes.ExecutionResult memory result)
    {
        // Check: Token, amount and caller balance
        if (token != wrappedNative) {
            return _failedResult(token, "Only wrapped native supported");
        }
        if (amount == 0) {
            return _failedResult(token, "Zero amount");
        }
        if (!_hasSufficientBalance(token, amount)) {
            return _failedResult(token, "Insufficient balance");
        }

        // Interaction: Pull the wrapped balance and unwrap it
        if (!_safeTransferFrom(token, msg.sender, address(this), amount)) {
            return _failedResult(token, "Transfer failed");
        }
        IWETH9(token).withdraw(amount);

        // Interaction: Hand the native value back through the rail's deposit entry, which is not a payer receipt
        bool returned;
        try IPaymentRails(msg.sender).returnNative{ value: amount }(token) {
            returned = true;
        } catch { }
        if (!returned) {
            // Re-wrap and return the balance so a caller that cannot take value is a soft failure
            IWETH9(token).deposit{ value: amount }();
            IERC20(token).safeTransfer(msg.sender, amount);
            return _failedResult(token, "Native transfer failed");
        }

        // Log: Emit unwrap event
        emit Unwrapped(msg.sender, amount);

        return _successResult(amount, Constants.NATIVE_TOKEN, "");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        USER-FACING CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IActionModule
    function validate(
        address token,
        uint256 amount,
        bytes calldata /* params */
    )
        external
        view
        override(ActionModuleBase, IActionModule)
        returns (bool isValid, string memory reason)
    {
        if (token != wrappedNative) {
            return (false, "Only wrapped native supported");
        }

        if (amount == 0) {
            return (false, "Zero amount");
        }

        if (!_hasSufficientBalance(token, amount)) {
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
        return "UNWRAP";
    }
}
