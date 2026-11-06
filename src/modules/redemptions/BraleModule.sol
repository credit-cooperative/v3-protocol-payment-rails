// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IBraleModule } from "../../interfaces/IBraleModule.sol";
import { IActionModule } from "../../interfaces/IActionModule.sol";
import { ActionModuleBase } from "../../abstracts/ActionModuleBase.sol";
import { DataTypes } from "../../types/DataTypes.sol";
import { Errors } from "../../libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title BraleModule
/// @author Credit Cooperative
/// @notice See the documentation in {IBraleModule}.
/// @dev Async redemption: tokens go straight from the PaymentRails to the Brale deposit address and the
///      USDC comes back off-chain later. Fee-on-transfer and sender-fee tokens are NOT supported (they
///      revert). The module holds no funds.
contract BraleModule is IBraleModule, ActionModuleBase, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBraleModule
    bytes32 public constant override REDEMPTION_ID_TYPEHASH =
        keccak256("BraleRedemption(uint256 chainId,address module,uint256 nonce)");

    /*//////////////////////////////////////////////////////////////////////////
                                IMMUTABLE STATE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBraleModule
    address public immutable override paymentRails;

    /*//////////////////////////////////////////////////////////////////////////
                                MUTABLE STATE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBraleModule
    uint256 public override redemptionNonce;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param _paymentRails Authorized PaymentRails caller for execute().
    /// @param _owner Owner for Ownable2Step (can only return stray tokens to the PaymentRails).
    constructor(address _paymentRails, address _owner) Ownable(_owner) {
        if (_paymentRails == address(0)) revert Errors.BraleModule_ZeroPaymentRails();
        paymentRails = _paymentRails;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            OWNERSHIP OVERRIDES
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Disables renounceOwnership() so stray tokens can always be returned to the PaymentRails.
    function renounceOwnership() public pure override {
        revert Errors.BraleModule_OwnershipCannotBeRenounced();
    }

    /*//////////////////////////////////////////////////////////////////////////
                            NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IActionModule
    function execute(
        address token,
        uint256 amount,
        bytes calldata params
    )
        external
        override(ActionModuleBase, IActionModule)
        nonReentrant
        returns (DataTypes.ExecutionResult memory result)
    {
        if (msg.sender != paymentRails) {
            revert Errors.BraleModule_NotPaymentRails(msg.sender, paymentRails);
        }

        (bool valid, string memory reason, DataTypes.BraleRedemptionParams memory p) = _validate(token, amount, params);
        if (!valid) {
            return _failedResult(token, reason);
        }

        // Effects: reserve the nonce before the external transfer.
        uint256 nonce = redemptionNonce;
        redemptionNonce = nonce + 1;
        bytes32 redemptionId = computeRedemptionId(nonce);

        // Snapshot both sides to enforce the exact amount (mirrors AtumModule I-06): fee-on-transfer and
        // sender-fee tokens would otherwise break rails accounting, the event and the Brale credit.
        uint256 depositBefore = IERC20(token).balanceOf(p.depositAddress);
        uint256 railsBefore = IERC20(token).balanceOf(msg.sender);

        // Interactions: move tokens directly from the PaymentRails to the Brale deposit address.
        // No event or external effect precedes this, so restoring the nonce on failure is safe.
        if (!_safeTransferFrom(token, msg.sender, p.depositAddress, amount)) {
            redemptionNonce = nonce;
            return _failedResult(token, "Token transfer failed");
        }

        {
            uint256 depositAfter = IERC20(token).balanceOf(p.depositAddress);
            uint256 delivered = depositAfter > depositBefore ? depositAfter - depositBefore : 0;
            if (delivered != amount) {
                revert Errors.BraleModule_UnexpectedDeliveredAmount(amount, delivered);
            }

            uint256 railsAfter = IERC20(token).balanceOf(msg.sender);
            uint256 debited = railsBefore > railsAfter ? railsBefore - railsAfter : 0;
            if (debited != amount) {
                revert Errors.BraleModule_UnexpectedDebitedAmount(amount, debited);
            }
        }

        // Both checks passed, so the delivered amount equals `amount`.
        emit RedemptionInitiated(redemptionId, token, p.depositAddress, nonce, amount, msg.sender, p.outputToken);

        return _successResult(0, p.outputToken, abi.encode(redemptionId));
    }

    /// @inheritdoc IBraleModule
    function returnToPaymentRails(address token) external override onlyOwner nonReentrant returns (uint256 amount) {
        amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) revert Errors.BraleModule_NothingToReturn(token);

        IERC20(token).safeTransfer(paymentRails, amount);
        emit TokensReturned(token, amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IActionModule
    function validate(
        address token,
        uint256 amount,
        bytes calldata params
    )
        external
        view
        override(ActionModuleBase, IActionModule)
        returns (bool isValid, string memory reason)
    {
        (isValid, reason,) = _validate(token, amount, params);
    }

    /// @inheritdoc IActionModule
    /// @dev Gross 1:1 USD par scaled between token decimals, before any Brale fee. Never reverts.
    function estimateOutput(
        address token,
        uint256 amount,
        bytes calldata params
    )
        external
        view
        override(ActionModuleBase, IActionModule)
        returns (uint256 estimatedOutput, address outputToken)
    {
        (bool valid,, DataTypes.BraleRedemptionParams memory p) = _validate(token, amount, params);
        if (!valid) return (0, token);

        (bool inOk, uint8 inDec) = _tryDecimals(token);
        (bool outOk, uint8 outDec) = _tryDecimals(p.outputToken);
        if (!inOk || !outOk) return (0, p.outputToken);

        if (outDec >= inDec) {
            uint256 up = uint256(outDec) - uint256(inDec);
            if (up > 77) return (0, p.outputToken);
            (bool ok, uint256 v) = Math.tryMul(amount, 10 ** up);
            return (ok ? v : 0, p.outputToken);
        }

        uint256 down = uint256(inDec) - uint256(outDec);
        return (down > 77 ? 0 : amount / 10 ** down, p.outputToken);
    }

    /// @inheritdoc IActionModule
    function moduleType() external pure override(ActionModuleBase, IActionModule) returns (string memory) {
        return "BRALE_REDEMPTION";
    }

    /// @inheritdoc IBraleModule
    function computeRedemptionId(uint256 nonce) public view override returns (bytes32) {
        return keccak256(abi.encode(REDEMPTION_ID_TYPEHASH, block.chainid, address(this), nonce));
    }

    /// @inheritdoc IBraleModule
    function encodeParams(DataTypes.BraleRedemptionParams calldata params)
        external
        pure
        override
        returns (bytes memory)
    {
        return abi.encode(params.depositAddress, params.outputToken, params.minAmount);
    }

    /// @inheritdoc IBraleModule
    function decodeParams(bytes calldata encoded)
        public
        pure
        override
        returns (DataTypes.BraleRedemptionParams memory params)
    {
        (params.depositAddress, params.outputToken, params.minAmount) = abi.decode(encoded, (address, address, uint256));
    }

    /*//////////////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Shared by execute and validate. No balance, enabled or caller checks (PaymentRails owns those).
    function _validate(
        address token,
        uint256 amount,
        bytes calldata params
    )
        private
        view
        returns (bool, string memory, DataTypes.BraleRedemptionParams memory p)
    {
        if (amount == 0) return (false, "Zero amount", p);
        if (params.length < 96) return (false, "Invalid params encoding", p);

        try this.decodeParams(params) returns (DataTypes.BraleRedemptionParams memory decoded) {
            p = decoded;
        } catch {
            return (false, "Invalid params encoding", p);
        }

        string memory reason = _depositReason(p, token);
        if (bytes(reason).length != 0) return (false, reason, p);
        if (p.outputToken == address(0)) return (false, "Zero output token", p);
        if (p.outputToken == token) return (false, "Output token equals input token", p);
        if (p.depositAddress == p.outputToken) return (false, "Deposit address is output token", p);
        reason = _minAmountReason(p, amount);
        if (bytes(reason).length != 0) return (false, reason, p);

        return (true, "", p);
    }

    /// @dev Rejection reason for a bad deposit address, or "" if it is acceptable.
    function _depositReason(
        DataTypes.BraleRedemptionParams memory p,
        address token
    )
        private
        view
        returns (string memory)
    {
        if (p.depositAddress == address(0)) return "Zero deposit address";
        if (p.depositAddress == paymentRails) return "Deposit address is PaymentRails";
        if (p.depositAddress == address(this)) return "Deposit address is module";
        if (p.depositAddress == token) return "Deposit address is input token";
        return "";
    }

    /// @dev Rejection reason for a bad minimum-amount config or an amount below it, or "" if acceptable.
    function _minAmountReason(
        DataTypes.BraleRedemptionParams memory p,
        uint256 amount
    )
        private
        pure
        returns (string memory)
    {
        if (p.minAmount == 0) return "Zero minimum amount";
        if (amount < p.minAmount) return "Below minimum redemption";
        return "";
    }

    /// @dev Reads `decimals()` via staticcall so a codeless or non-conforming target cannot revert the caller.
    ///      Copies at most 32 bytes of returndata so a hostile token cannot burn gas with a returndata bomb.
    function _tryDecimals(address t) private view returns (bool ok, uint8 d) {
        bytes memory data = abi.encodeCall(IERC20Metadata.decimals, ());
        uint256 v;
        uint256 size;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, 0)
            ok := staticcall(gas(), t, add(data, 0x20), mload(data), ptr, 0x20)
            size := returndatasize()
            v := mload(ptr)
        }
        if (!ok || size < 32) return (false, 0);
        if (v > type(uint8).max) return (false, 0);
        return (true, uint8(v));
    }
}
