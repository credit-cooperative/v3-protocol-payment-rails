// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IActionModule } from "../../../src/interfaces/IActionModule.sol";
import { INativeActionModule } from "../../../src/interfaces/INativeActionModule.sol";
import { DataTypes } from "../../../src/types/DataTypes.sol";
import { Constants } from "../../../src/libraries/Constants.sol";

/// @dev Configurable native module for PaymentRails unit tests: keeps the value it is sent and can be told to
///      succeed, return a failed result, revert, or deny native support.
contract MockNativeActionModule is IActionModule, INativeActionModule {
    bool public shouldRevert;
    string public revertReason;
    bool public shouldReturnFalse;
    bool public supportsNative = true;
    bool public validationResult = true;
    string public validationReason;

    uint256 public totalReceived;
    uint256 public lastAmount;

    function setExecuteRevert(bool _revert, string memory _reason) external {
        shouldRevert = _revert;
        revertReason = _reason;
    }

    function setReturnFalse(bool _returnFalse) external {
        shouldReturnFalse = _returnFalse;
    }

    function setSupportsNative(bool _supports) external {
        supportsNative = _supports;
    }

    function setValidationResult(bool _valid, string memory _reason) external {
        validationResult = _valid;
        validationReason = _reason;
    }

    function executeNative(
        uint256 amount,
        bytes calldata
    )
        external
        payable
        override
        returns (DataTypes.ExecutionResult memory)
    {
        if (shouldRevert) revert(revertReason);
        totalReceived += msg.value;
        lastAmount = amount;
        if (shouldReturnFalse) {
            return DataTypes.ExecutionResult({
                success: false,
                amountOut: 0,
                outputToken: Constants.NATIVE_TOKEN,
                data: "",
                failureReason: "Mock refused"
            });
        }
        return DataTypes.ExecutionResult({
            success: true, amountOut: amount, outputToken: Constants.NATIVE_TOKEN, data: "", failureReason: ""
        });
    }

    function execute(
        address token,
        uint256,
        bytes calldata
    )
        external
        pure
        override
        returns (DataTypes.ExecutionResult memory)
    {
        return DataTypes.ExecutionResult({
            success: false, amountOut: 0, outputToken: token, data: "", failureReason: "Native input only"
        });
    }

    function validate(
        address token,
        uint256 amount,
        bytes calldata
    )
        external
        view
        override
        returns (bool, string memory)
    {
        if (!validationResult) return (false, validationReason);
        if (token != Constants.NATIVE_TOKEN) return (false, "Native input only");
        if (msg.sender.balance < amount) return (false, "Insufficient balance");
        return (true, "");
    }

    function estimateOutput(address, uint256 amount, bytes calldata) external pure override returns (uint256, address) {
        return (amount, Constants.NATIVE_TOKEN);
    }

    function moduleType() external pure override returns (string memory) {
        return "NATIVE_MOCK";
    }

    function supportsNativeInput() external view override returns (bool) {
        return supportsNative;
    }
}

/// @dev Looks like an action module but does not expose supportsNativeInput at all.
contract NonNativeModuleMock {
    function moduleType() external pure returns (string memory) {
        return "PLAIN";
    }
}
