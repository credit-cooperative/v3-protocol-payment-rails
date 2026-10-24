// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IWrapModule } from "../../interfaces/IWrapModule.sol";
import { INativeActionModule } from "../../interfaces/INativeActionModule.sol";
import { IActionModule } from "../../interfaces/IActionModule.sol";
import { IWETH9 } from "../../interfaces/IWETH9.sol";
import { ActionModuleBase } from "../../abstracts/ActionModuleBase.sol";
import { DataTypes } from "../../types/DataTypes.sol";
import { Constants } from "../../libraries/Constants.sol";
import { Errors } from "../../libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title WrapModule
/// @author Credit Cooperative
/// @notice See the documentation in {IWrapModule}.
contract WrapModule is IWrapModule, ActionModuleBase, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IWrapModule
    address public immutable wrappedNative;

    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param wrappedNative_ The chain's wrapped-native token this module deposits into
    constructor(address wrappedNative_) {
        // Check: Wrapped-native is a contract
        if (wrappedNative_ == address(0)) {
            revert Errors.WrapModule_ZeroWrappedNative();
        }
        if (wrappedNative_.code.length == 0) {
            revert Errors.WrapModule_WrappedNativeNotContract(wrappedNative_);
        }

        wrappedNative = wrappedNative_;
    }

    /*//////////////////////////////////////////////////////////////////////////
                        USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc INativeActionModule
    /// @dev Emits a {Wrapped} event.
    function executeNative(
        uint256 amount,
        bytes calldata /* params */
    )
        external
        payable
        nonReentrant
        returns (DataTypes.ExecutionResult memory result)
    {
        // Check: Non-zero value matching the requested amount
        if (amount == 0 || msg.value != amount) {
            revert Errors.WrapModule_ValueMismatch(amount, msg.value);
        }

        // Interaction: Wrap, then hand the wrapped balance back to the caller
        uint256 balanceBefore = IERC20(wrappedNative).balanceOf(address(this));
        IWETH9(wrappedNative).deposit{ value: amount }();

        // Check: Wrapper credited the exact amount
        uint256 credited = IERC20(wrappedNative).balanceOf(address(this)) - balanceBefore;
        if (credited != amount) {
            revert Errors.WrapModule_WrapAmountMismatch(amount, credited);
        }
        IERC20(wrappedNative).safeTransfer(msg.sender, amount);

        // Log: Emit wrap event
        emit Wrapped(msg.sender, amount);

        return _successResult(amount, wrappedNative, "");
    }

    /// @inheritdoc IActionModule
    /// @dev ERC-20 input is not an action of this module; native value arrives through {executeNative}.
    function execute(
        address token,
        uint256, /* amount */
        bytes calldata /* params */
    )
        external
        pure
        override(ActionModuleBase, IActionModule)
        returns (DataTypes.ExecutionResult memory result)
    {
        return _failedResult(token, "Native input only");
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
        if (token != Constants.NATIVE_TOKEN) {
            return (false, "Native input only");
        }

        if (amount == 0) {
            return (false, "Zero amount");
        }

        if (msg.sender.balance < amount) {
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
        view
        override(ActionModuleBase, IActionModule)
        returns (uint256 estimatedOutput, address outputToken)
    {
        return (amount, wrappedNative);
    }

    /// @inheritdoc IActionModule
    function moduleType() external pure override(ActionModuleBase, IActionModule) returns (string memory) {
        return "WRAP";
    }

    /// @inheritdoc INativeActionModule
    function supportsNativeInput() external pure returns (bool) {
        return true;
    }
}
