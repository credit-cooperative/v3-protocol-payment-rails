// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IBraleModuleFactory
/// @notice Interface for the factory that deploys and tracks BraleModule instances.
/// @dev BraleModule is bound to one immutable `paymentRails`, so each PaymentRails needs its own dedicated
/// module instance. Supports both CREATE (simple) and CREATE2 (deterministic).
///
/// Deployment is owner-gated: only the factory owner may deploy modules, so every registry entry was
/// authored by this organization. `paymentRails` only has to be a contract. The factory does not enforce
/// one module per PaymentRails; that is an operational rule.
///
/// Registration is provenance, not authorization: a module only becomes live once the PaymentRails owner
/// points a token config at it via `configureToken`. The off-chain redemption service should allowlist
/// module emitters from this registry and verify `module.paymentRails()`.
interface IBraleModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new BraleModule instance is deployed.
    /// @param module The address of the deployed BraleModule contract.
    /// @param paymentRails The PaymentRails instance the module is wired to.
    /// @param owner The initial owner of the BraleModule contract.
    event BraleModuleCreated(address indexed module, address indexed paymentRails, address indexed owner);

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new BraleModule instance using CREATE.
    /// @dev Emits a {BraleModuleCreated} event.
    ///
    /// Requirements:
    /// - caller must be the factory owner
    /// - `owner` must not be `address(0)`
    /// - `paymentRails` must not be `address(0)`
    /// - `paymentRails` must be a contract
    ///
    /// @param owner The initial owner of the BraleModule. May differ from the PaymentRails owner.
    /// @param paymentRails The PaymentRails instance authorized to call the module's execute().
    /// @return module The address of the deployed BraleModule contract.
    function create(address owner, address paymentRails) external returns (address module);

    /// @notice Deploy a new BraleModule instance using CREATE2 for deterministic addressing.
    /// @dev Emits a {BraleModuleCreated} event. The deployment address can be predicted off-chain
    /// via {predictDeterministicAddress}. Reverts if a contract already exists at the predicted address.
    ///
    /// Requirements:
    /// - caller must be the factory owner
    /// - `owner` must not be `address(0)`
    /// - `paymentRails` must not be `address(0)`
    /// - `paymentRails` must be a contract
    /// - The `(msg.sender, owner, paymentRails, salt)` combination must not have been used before. The
    ///   caller is part of the key because the CREATE2 salt is bound to it, so the same salt used by
    ///   two deployers yields two distinct addresses.
    ///
    /// @param owner The initial owner of the BraleModule.
    /// @param paymentRails The PaymentRails instance authorized to call the module's execute().
    /// @param salt The salt for CREATE2 address derivation.
    /// @return module The address of the deployed BraleModule contract.
    function createDeterministic(address owner, address paymentRails, bytes32 salt) external returns (address module);

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Predict the address of a deterministic deployment.
    /// @param deployer The address that will call {createDeterministic}. The salt is bound to it, so the
    ///        predicted address differs per deployer. Passed explicitly because prediction is an off-chain
    ///        read and the party asking is usually not the party deploying.
    /// @param owner The initial owner that would be passed to {createDeterministic}.
    /// @param paymentRails The PaymentRails that would be passed to {createDeterministic}.
    /// @param salt The salt that would be passed to {createDeterministic}.
    /// @return predicted The address where the BraleModule would be deployed.
    function predictDeterministicAddress(
        address deployer,
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

    /// @notice Return all BraleModule instances deployed by this factory.
    /// @dev May be expensive for off-chain calls if the array is very large. Prefer event indexing at scale.
    /// @return modules Array of deployed BraleModule addresses.
    function getDeployedModules() external view returns (address[] memory modules);

    /// @notice Return the total number of BraleModule instances deployed by this factory.
    /// @return count Number of deployed modules.
    function getModuleCount() external view returns (uint256 count);

    /// @notice Return all BraleModule instances deployed for a given PaymentRails.
    /// @dev Provenance only: the wired module is `getTokenConfig(token).actionModule`.
    /// @param paymentRails The PaymentRails instance to look up.
    /// @return modules Array of BraleModule addresses wired to `paymentRails`.
    function getModulesForPaymentRails(address paymentRails) external view returns (address[] memory modules);
}
