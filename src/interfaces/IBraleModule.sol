// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IActionModule } from "./IActionModule.sol";
import { DataTypes } from "../types/DataTypes.sol";

/// @title IBraleModule
/// @notice Interface for the module that redeems a Brale-issued stablecoin held by a PaymentRails.
/// @dev Flow: anyone calls `rails.executeAction(token, amount)`; the module moves exactly `amount` of `token`
/// from the rails straight to the Brale custodial deposit address configured in the rails' `moduleParams`
/// (a {DataTypes.BraleRedemptionParams}) and emits {RedemptionInitiated} with a unique `redemptionId`.
/// An off-chain service reads that event and asks Brale to send `outputToken` (USDC) back to the rails.
/// The module rejects any `amount` below the configured `minAmount`. The module never holds funds. The deposit address
/// and USDC address are the rails owner's configuration, so the off-chain service must treat the event as a hint and
/// validate it against its own registry.
/// Fee-on-transfer and sender-fee tokens are NOT supported (they revert).
/// See src/modules/redemptions/README.md for the off-chain service spec.
interface IBraleModule is IActionModule {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when tokens are delivered to the Brale deposit address for redemption into `outputToken`.
    /// @param redemptionId Unique id: keccak256(abi.encode(REDEMPTION_ID_TYPEHASH, chainid, module, nonce)).
    /// @param token Brale-issued token delivered.
    /// @param depositAddress Brale custodial address that received `amount`.
    /// @param nonce Module-local sequence number used to derive `redemptionId`.
    /// @param amount Amount actually credited to `depositAddress` (== requested amount).
    /// @param paymentRails Rails that funded the redemption and must receive `outputToken`.
    /// @param outputToken Token Brale is expected to deliver (USDC on this chain).
    event RedemptionInitiated(
        bytes32 indexed redemptionId,
        address indexed token,
        address indexed depositAddress,
        uint256 nonce,
        uint256 amount,
        address paymentRails,
        address outputToken
    );

    /// @notice Emitted when the owner returns a stray token balance to the PaymentRails.
    /// @param token The token returned.
    /// @param amount The amount returned.
    event TokensReturned(address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Type hash that domain-separates redemption ids.
    /// @return The keccak256 of "BraleRedemption(uint256 chainId,address module,uint256 nonce)".
    function REDEMPTION_ID_TYPEHASH() external view returns (bytes32);

    /// @notice The only caller allowed to run `execute`; also the destination of `returnToPaymentRails`.
    /// @return The PaymentRails address.
    function paymentRails() external view returns (address);

    /// @notice The next nonce to use; also the number of redemptions initiated so far.
    /// @return The current redemption nonce.
    function redemptionNonce() external view returns (uint256);

    /// @notice Computes the redemption id for a given nonce on this chain and module.
    /// @param nonce The module-local nonce.
    /// @return The redemption id.
    function computeRedemptionId(uint256 nonce) external view returns (bytes32);

    /// @notice ABI-encodes a {DataTypes.BraleRedemptionParams} struct into bytes for
    /// {IPaymentRails.configureToken}.
    ///
    /// Notes:
    /// - Pure function (no state access).
    /// - Inverse of {decodeParams}.
    ///
    /// @param params Redemption parameters to encode.
    /// @return ABI-encoded bytes representation.
    function encodeParams(DataTypes.BraleRedemptionParams calldata params) external pure returns (bytes memory);

    /// @notice Decodes ABI-encoded bytes into a {DataTypes.BraleRedemptionParams} struct.
    ///
    /// Notes:
    /// - Pure function (no state access).
    /// - Inverse of {encodeParams}.
    /// - Reverts if the bytes are not valid ABI-encoded `(address, address, uint256)`.
    ///
    /// @param encoded ABI-encoded parameter bytes.
    /// @return params Decoded BraleRedemptionParams struct.
    function decodeParams(bytes calldata encoded) external pure returns (DataTypes.BraleRedemptionParams memory params);

    /*//////////////////////////////////////////////////////////////////////////
                            NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Sends the module's full balance of `token` to the PaymentRails.
    /// @dev Recovery for tokens sent to the module by mistake. The destination is fixed, so the owner
    /// cannot extract funds. Emits {TokensReturned}.
    ///
    /// Requirements:
    /// - caller must be the owner
    /// - the module's balance of `token` must be non-zero
    ///
    /// @param token The token to return.
    /// @return amount The amount returned.
    function returnToPaymentRails(address token) external returns (uint256 amount);
}
