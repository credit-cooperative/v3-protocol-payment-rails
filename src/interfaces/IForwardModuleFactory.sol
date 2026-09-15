// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IForwardModuleFactory
/// @notice Interface for the factory that deploys and tracks ForwardModule instances.
/// @dev ForwardModule is stateless and takes no constructor arguments, so every instance this
/// factory deploys is interchangeable and a single deployment can be shared by any number of
/// PaymentRails instances. Supports both CREATE (simple) and CREATE2 (deterministic) deployment.
///
/// Deployment is permissionless, unlike {ICowSwapModuleFactory}. The registry here is keyed only
/// by module address and carries no per-PaymentRails index, so a deployment by a stranger asserts
/// nothing about any PaymentRails and cannot be surfaced under a victim's entry. A module is bound
/// to a PaymentRails solely by that instance's owner calling `configureToken`, and the recipient of
/// a forward comes from the per-token params the PaymentRails owner sets — never from the factory.
interface IForwardModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new ForwardModule instance is deployed.
    /// @param module The address of the deployed ForwardModule contract.
    /// @param deployer The address that called the factory.
    event ForwardModuleCreated(address indexed module, address indexed deployer);

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new ForwardModule instance using CREATE.
    /// @dev Emits a {ForwardModuleCreated} event.
    /// @return module The address of the deployed ForwardModule contract.
    function create() external returns (address module);

    /// @notice Deploy a new ForwardModule instance using CREATE2 for deterministic addressing.
    /// @dev Emits a {ForwardModuleCreated} event. The deployment address can be predicted off-chain
    /// via {predictDeterministicAddress}. Reverts if a contract already exists at the predicted address.
    ///
    /// Requirements:
    /// - `salt` must not have been used before on this factory
    ///
    /// @param salt The salt for CREATE2 address derivation.
    /// @return module The address of the deployed ForwardModule contract.
    function createDeterministic(bytes32 salt) external returns (address module);

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Predict the address of a deterministic deployment.
    /// @dev ForwardModule has no constructor arguments, so the address depends only on the salt.
    /// A caller who broadcasts a salt can have it taken by anyone; treat a predicted address as
    /// reserved only once {isDeployedModule} confirms it.
    /// @param salt The salt that would be passed to {createDeterministic}.
    /// @return predicted The address where the ForwardModule would be deployed.
    function predictDeterministicAddress(bytes32 salt) external view returns (address predicted);

    /// @notice Check whether an address was deployed by this factory.
    /// @param module The address to check.
    /// @return isModule True if the address was deployed by this factory.
    function isDeployedModule(address module) external view returns (bool isModule);

    /// @notice Return all ForwardModule instances deployed by this factory.
    /// @dev May be expensive for off-chain calls if the array is very large. Prefer event indexing at scale.
    /// @return modules Array of deployed ForwardModule addresses.
    function getDeployedModules() external view returns (address[] memory modules);

    /// @notice Return the total number of ForwardModule instances deployed by this factory.
    /// @return count Number of deployed modules.
    function getModuleCount() external view returns (uint256 count);
}
