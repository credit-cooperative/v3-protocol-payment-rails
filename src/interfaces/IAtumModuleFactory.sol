// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IAtumModuleFactory
/// @notice Interface for the factory that deploys and tracks AtumModule instances.
/// @dev AtumModule is stateful (owns pulled source balances, immutable `paymentRails` and `permit2`),
/// so each PaymentRails needs its own dedicated module instance. This factory deploys them with the
/// chain-specific Permit2 fixed as a factory immutable, so the registry guarantees both bytecode and
/// wiring of every registered module. Supports both CREATE (simple) and CREATE2 (deterministic).
///
/// Deployment is restricted to the factory owner and owner-approved factory operators, so every
/// registry entry was authored by this organization (Certora L-01). The PaymentRails owner does not
/// need to be the caller; the factory owner or an operator deploys on their behalf. `paymentRails`
/// only has to be a contract: the factory is not bound to any PaymentRailsFactory, so which rails a
/// module serves is the caller's call, and one factory serves rails from every PaymentRailsFactory
/// version.
///
/// Registration is provenance, not authorization: a module only becomes live once the PaymentRails
/// owner points a token config at it via `configureToken`. Verify `module.owner()`,
/// `module.keeper()` and `module.paymentRails()` before wiring a module.
///
/// Factory operators: the owner may approve operators via {setFactoryOperator}; they share the
/// owner's creation rights and nothing else. Approvals survive an ownership transfer — a new owner
/// must review the {FactoryOperatorSet} history and revoke any operator it does not trust.
interface IAtumModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new AtumModule instance is deployed.
    /// @param module The address of the deployed AtumModule contract.
    /// @param paymentRails The PaymentRails instance the module is wired to.
    /// @param owner The initial owner of the AtumModule contract.
    /// @param keeper The initial keeper of the AtumModule contract. Not indexed: the event already
    ///        carries the maximum three indexed topics, and the keeper is recoverable from the
    ///        module's own `KeeperSet(address(0), keeper)` emitted in the same transaction.
    /// @dev Certora I-03. The initial keeper is the hot key authorising movement of every token
    ///      the module holds, and it was previously absent from both this event and the module's
    ///      own logs, so incident response could not correlate a drain to an authorised key.
    event AtumModuleCreated(
        address indexed module, address indexed paymentRails, address indexed owner, address keeper
    );

    /// @notice Emitted when the factory owner approves or revokes a factory operator.
    /// @param sender The factory owner that made the change.
    /// @param operator The account whose approval changed.
    /// @param approved True if approved, false if revoked.
    event FactoryOperatorSet(address indexed sender, address indexed operator, bool indexed approved);

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new AtumModule instance using CREATE.
    /// @dev Emits an {AtumModuleCreated} event.
    ///
    /// Requirements:
    /// - caller must be the factory owner or an approved factory operator (Certora L-01; see {setFactoryOperator})
    /// - `owner` must not be `address(0)`
    /// - `paymentRails` must not be `address(0)`
    /// - `keeper` must not be `address(0)`
    /// - `paymentRails` must be a contract
    ///
    /// @param owner The initial owner of the AtumModule (can rotate the keeper and pause). May differ
    /// from the PaymentRails owner.
    /// @param paymentRails The PaymentRails instance authorized to call the module's execute().
    /// @param keeper The keeper authorized to invalidate digests on the module.
    /// @return module The address of the deployed AtumModule contract.
    function create(address owner, address paymentRails, address keeper) external returns (address module);

    /// @notice Deploy a new AtumModule instance using CREATE2 for deterministic addressing.
    /// @dev Emits an {AtumModuleCreated} event. The deployment address can be predicted off-chain
    /// via {predictDeterministicAddress}. Reverts if a contract already exists at the predicted address.
    ///
    /// Requirements:
    /// - caller must be the factory owner or an approved factory operator (Certora L-01; see {setFactoryOperator})
    /// - `owner` must not be `address(0)`
    /// - `paymentRails` must not be `address(0)`
    /// - `keeper` must not be `address(0)`
    /// - `paymentRails` must be a contract
    /// - The `(msg.sender, owner, paymentRails, keeper, salt)` combination must not have been used
    ///   before. The caller -- the owner or the operator submitting the call -- is part of
    ///   the key because the CREATE2 salt is bound to it (Certora I-04), so the same salt used by
    ///   two deployers yields two distinct addresses.
    /// - The resulting address therefore depends on which account sends the transaction (the owner
    ///   or each operator). Predict with that sender as `deployer`, and have deploy tooling compare
    ///   the returned address to the prediction.
    ///
    /// @param owner The initial owner of the AtumModule (can rotate the keeper and pause).
    /// @param paymentRails The PaymentRails instance authorized to call the module's execute().
    /// @param keeper The keeper authorized to invalidate digests on the module.
    /// @param salt The salt for CREATE2 address derivation.
    /// @return module The address of the deployed AtumModule contract.
    function createDeterministic(
        address owner,
        address paymentRails,
        address keeper,
        bytes32 salt
    )
        external
        returns (address module);

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

    /// @notice The Permit2 contract every deployed module is wired to.
    /// @return The Permit2 address.
    function permit2() external view returns (address);

    /// @notice Predict the address of a deterministic deployment.
    /// @param deployer The address that will call {createDeterministic}: the factory owner or the
    ///        approved factory operator submitting the deployment. The salt is bound to it
    ///        (Certora I-04), so the predicted address differs per deployer and a module predicted
    ///        for one operator lands elsewhere if another operator or the owner deploys it. Passed
    ///        explicitly rather than taken from `msg.sender` because prediction is an off-chain read
    ///        and the party asking is usually not the party deploying. Deploy tooling should compare
    ///        the address returned by {createDeterministic} to this prediction.
    /// @param owner The initial owner that would be passed to {createDeterministic}.
    /// @param paymentRails The PaymentRails that would be passed to {createDeterministic}.
    /// @param keeper The keeper that would be passed to {createDeterministic}.
    /// @param salt The salt that would be passed to {createDeterministic}.
    /// @return predicted The address where the AtumModule would be deployed.
    function predictDeterministicAddress(
        address deployer,
        address owner,
        address paymentRails,
        address keeper,
        bytes32 salt
    )
        external
        view
        returns (address predicted);

    /// @notice Check whether an address was deployed by this factory.
    /// @param module The address to check.
    /// @return isModule True if the address was deployed by this factory.
    function isDeployedModule(address module) external view returns (bool isModule);

    /// @notice Return all AtumModule instances deployed by this factory.
    /// @dev May be expensive for off-chain calls if the array is very large. Prefer event indexing at scale.
    /// @return modules Array of deployed AtumModule addresses.
    function getDeployedModules() external view returns (address[] memory modules);

    /// @notice Return the total number of AtumModule instances deployed by this factory.
    /// @return count Number of deployed modules.
    function getModuleCount() external view returns (uint256 count);

    /// @notice Return all AtumModule instances deployed for a given PaymentRails.
    /// @dev Multiple modules per PaymentRails are possible (e.g. redeployments); the last entry
    /// is the most recently deployed. Provenance only: the wired module is
    /// `getTokenConfig(token).actionModule`.
    /// @param paymentRails The PaymentRails instance to look up.
    /// @return modules Array of AtumModule addresses wired to `paymentRails`.
    function getModulesForPaymentRails(address paymentRails) external view returns (address[] memory modules);
}
