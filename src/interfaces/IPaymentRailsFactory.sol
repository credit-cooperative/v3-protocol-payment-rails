// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IPaymentRailsFactory
/// @notice Interface for the factory that deploys and tracks PaymentRails instances.
/// @dev Supports both CREATE (simple) and CREATE2 (deterministic) deployment. Maintains an on-chain
/// registry of all deployed instances for trust verification. Creation is restricted to the factory
/// owner and owner-approved factory operators.
///
/// Factory operators: the owner may approve operators via {setFactoryOperator}; they share the
/// owner's creation rights and nothing else. Approvals survive an ownership transfer — a new owner
/// must review the {FactoryOperatorSet} history and revoke any operator it does not trust.
interface IPaymentRailsFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new PaymentRails instance is deployed.
    /// @param paymentRails The address of the deployed PaymentRails contract.
    /// @param owner The initial owner of the PaymentRails contract.
    event PaymentRailsCreated(address indexed paymentRails, address indexed owner);

    /// @notice Emitted when the factory owner approves or revokes a factory operator.
    /// @param sender The factory owner that made the change.
    /// @param operator The account whose approval changed.
    /// @param approved True if approved, false if revoked.
    event FactoryOperatorSet(address indexed sender, address indexed operator, bool indexed approved);

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new PaymentRails instance using CREATE.
    /// @dev Emits a {PaymentRailsCreated} event. Restricted to the factory owner or an approved factory
    /// operator so the registry only lists instances this organization deployed.
    ///
    /// Requirements:
    /// - caller must be the factory owner or an approved factory operator (see {setFactoryOperator})
    /// - `railsOwner` must not be `address(0)`
    ///
    /// @param railsOwner The initial owner of the deployed PaymentRails contract.
    /// @return paymentRails The address of the deployed PaymentRails contract.
    function create(address railsOwner) external returns (address paymentRails);

    /// @notice Deploy a new PaymentRails instance using CREATE2 for deterministic addressing.
    /// @dev Emits a {PaymentRailsCreated} event. The deployment address can be predicted off-chain
    /// via {predictDeterministicAddress}. Reverts if a contract already exists at the predicted address.
    ///
    /// Caller-unbound salt: the CREATE2 salt is not bound to the caller, so another authorized
    /// caller (the owner or any approved operator) can submit the same arguments and salt first.
    /// The original transaction then reverts while the same contract lands at the same predicted
    /// address. This is griefing only; callers should check the predicted address for code before
    /// sending.
    ///
    /// Requirements:
    /// - caller must be the factory owner or an approved factory operator (see {setFactoryOperator})
    /// - `railsOwner` must not be `address(0)`
    /// - The `(railsOwner, salt)` combination must not have been used before
    ///
    /// @param railsOwner The initial owner of the deployed PaymentRails contract.
    /// @param salt The salt for CREATE2 address derivation.
    /// @return paymentRails The address of the deployed PaymentRails contract.
    function createDeterministic(address railsOwner, bytes32 salt) external returns (address paymentRails);

    /*//////////////////////////////////////////////////////////////////////////
                                OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Approve or revoke `operator` as a factory operator, allowed to call {create} and
    /// {createDeterministic} alongside the owner.
    /// @dev Emits a {FactoryOperatorSet} event, also when `approved` equals the current value, so
    /// re-running a batch never reverts. Operators can only create: they cannot manage operators or
    /// ownership, and nothing can remove a registry entry. No operator exists at deployment.
    ///
    /// Ownership transfer: approvals are NOT cleared when ownership changes. The operator set
    /// cannot be enumerated on-chain, so a new owner must rebuild it from {FactoryOperatorSet}
    /// events and revoke (`approved = false`) every operator it does not trust. A former owner that
    /// was explicitly approved stays an operator until revoked.
    ///
    /// Never approve a forwarder, multicall, Safe module or relayer as an operator: that would
    /// reopen creation to anyone who can call it.
    ///
    /// Requirements:
    /// - caller must be the factory owner
    /// - `operator` must not be `address(0)`
    ///
    /// @param operator The account to approve or revoke.
    /// @param approved True to approve, false to revoke.
    /// @return success Always true (kept for ABI parity with LineFactory).
    function setFactoryOperator(address operator, bool approved) external returns (bool success);

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Whether `operator` is an approved factory operator.
    /// @dev The owner is authorized to create regardless of this mapping, so this returns false for
    /// the owner unless it was explicitly approved.
    /// @param operator The account to check.
    /// @return approved True if `operator` may call {create} and {createDeterministic}.
    function factoryOperators(address operator) external view returns (bool approved);

    /// @notice Predict the address of a deterministic deployment.
    /// @param railsOwner The initial owner that would be passed to {createDeterministic}.
    /// @param salt The salt that would be passed to {createDeterministic}.
    /// @return predicted The address where the PaymentRails would be deployed.
    function predictDeterministicAddress(address railsOwner, bytes32 salt) external view returns (address predicted);

    /// @notice Check whether an address was deployed by this factory.
    /// @param instance The address to check.
    /// @return isInstance True if the address was deployed by this factory.
    function isDeployedInstance(address instance) external view returns (bool isInstance);

    /// @notice Return all PaymentRails instances deployed by this factory.
    /// @dev May be expensive for off-chain calls if the array is very large. Prefer event indexing at scale.
    /// @return instances Array of deployed PaymentRails addresses.
    function getDeployedInstances() external view returns (address[] memory instances);

    /// @notice Return the total number of PaymentRails instances deployed by this factory.
    /// @return count Number of deployed instances.
    function getInstanceCount() external view returns (uint256 count);
}
