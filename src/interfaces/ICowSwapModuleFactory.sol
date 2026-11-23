// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title ICowSwapModuleFactory
/// @notice Interface for the factory that deploys and tracks CowSwapModule instances.
/// @dev CowSwapModule is stateful (tracks pending orders, immutable `paymentRails`), so each
/// PaymentRails needs its own dedicated module instance. This factory deploys them with the
/// chain-specific configuration (GPv2Settlement, sequencer feed) fixed as factory immutables,
/// so the registry guarantees both bytecode and wiring of every registered module. Supports
/// both CREATE (simple) and CREATE2 (deterministic) deployment.
///
/// Deployment is restricted to the factory owner and owner-approved factory operators, so every
/// registry entry was authored by this organization. The factory cannot verify `paymentRails` is a
/// genuine PaymentRails; verify `module.paymentRails()` and `module.owner()` before wiring a module.
///
/// Registration is provenance, not authorization: a module only becomes live once the PaymentRails
/// owner points a token config at it via `configureToken`.
///
/// Factory operators: the owner may approve operators via {setFactoryOperator}; they share the
/// owner's creation rights and nothing else. Approvals survive an ownership transfer — a new owner
/// must review the {FactoryOperatorSet} history and revoke any operator it does not trust.
interface ICowSwapModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new CowSwapModule instance is deployed.
    /// @param module The address of the deployed CowSwapModule contract.
    /// @param paymentRails The PaymentRails instance the module is wired to.
    /// @param owner The initial owner of the CowSwapModule contract.
    event CowSwapModuleCreated(address indexed module, address indexed paymentRails, address indexed owner);

    /// @notice Emitted when the factory owner approves or revokes a factory operator.
    /// @param sender The factory owner that made the change.
    /// @param operator The account whose approval changed.
    /// @param approved True if approved, false if revoked.
    event FactoryOperatorSet(address indexed sender, address indexed operator, bool indexed approved);

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new CowSwapModule instance using CREATE.
    /// @dev Emits a {CowSwapModuleCreated} event.
    ///
    /// Requirements:
    /// - caller must be the factory owner or an approved factory operator (see {setFactoryOperator})
    /// - `owner` must not be `address(0)`
    /// - `paymentRails` must not be `address(0)`
    /// - `paymentRails` must have code
    ///
    /// @param owner The initial owner of the CowSwapModule (can cancel orders).
    /// @param paymentRails The PaymentRails instance authorized to call the module's execute().
    /// @return module The address of the deployed CowSwapModule contract.
    function create(address owner, address paymentRails) external returns (address module);

    /// @notice Deploy a new CowSwapModule instance using CREATE2 for deterministic addressing.
    /// @dev Emits a {CowSwapModuleCreated} event. The deployment address can be predicted off-chain
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
    /// - `owner` must not be `address(0)`
    /// - `paymentRails` must not be `address(0)`
    /// - `paymentRails` must have code
    /// - The `(owner, paymentRails, salt)` combination must not have been used before
    ///
    /// @param owner The initial owner of the CowSwapModule (can cancel orders).
    /// @param paymentRails The PaymentRails instance authorized to call the module's execute().
    /// @param salt The salt for CREATE2 address derivation.
    /// @return module The address of the deployed CowSwapModule contract.
    function createDeterministic(address owner, address paymentRails, bytes32 salt) external returns (address module);

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

    /// @notice The GPv2Settlement contract every deployed module is wired to.
    /// @return The GPv2Settlement address.
    function cowSettlement() external view returns (address);

    /// @notice The Chainlink L2 sequencer uptime feed passed to every deployed module.
    /// @dev Fixed at factory deployment: either `address(0)` for the L1 profile or a deployed
    /// contract. A non-zero address without code is rejected in the constructor, since every module
    /// the factory produced would then revert on its oracle read.
    /// @return The sequencer uptime feed address; `address(0)` on L1.
    function sequencerUptimeFeed() external view returns (address);

    /// @notice The sequencer grace period passed to every deployed module.
    /// @return The grace period, denoted in seconds.
    function sequencerGracePeriod() external view returns (uint256);

    /// @notice Predict the address of a deterministic deployment.
    /// @dev Pure address derivation — it does not check that the caller is authorized to perform the
    /// deployment. Since the constructor arguments are part of the derivation, a predicted address can
    /// only ever be occupied by a module with exactly these `(owner, paymentRails)` values.
    /// @param owner The initial owner that would be passed to {createDeterministic}.
    /// @param paymentRails The PaymentRails that would be passed to {createDeterministic}.
    /// @param salt The salt that would be passed to {createDeterministic}.
    /// @return predicted The address where the CowSwapModule would be deployed.
    function predictDeterministicAddress(
        address owner,
        address paymentRails,
        bytes32 salt
    )
        external
        view
        returns (address predicted);

    /// @notice Check whether an address was deployed by this factory.
    /// @param module The address to check.
    /// @return isModule True if the address was deployed by this factory.
    function isDeployedModule(address module) external view returns (bool isModule);

    /// @notice Return all CowSwapModule instances deployed by this factory.
    /// @dev May be expensive for off-chain calls if the array is very large. Prefer event indexing at scale.
    /// @return modules Array of deployed CowSwapModule addresses.
    function getDeployedModules() external view returns (address[] memory modules);

    /// @notice Return the total number of CowSwapModule instances deployed by this factory.
    /// @return count Number of deployed modules.
    function getModuleCount() external view returns (uint256 count);

    /// @notice Return all CowSwapModule instances deployed for a given PaymentRails.
    /// @dev Multiple modules per PaymentRails are possible (e.g. redeployments); the last entry is
    /// the most recent. Provenance only: the wired module is `getTokenConfig(token).actionModule`.
    /// @param paymentRails The PaymentRails instance to look up.
    /// @return modules Array of CowSwapModule addresses wired to `paymentRails`.
    function getModulesForPaymentRails(address paymentRails) external view returns (address[] memory modules);
}
