// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title ICCTPBridgeModuleFactory
/// @notice Interface for the factory that deploys and tracks CCTPBridgeModule instances.
/// @dev CCTPBridgeModule is stateless, so a single deployment can be shared by any number of
/// PaymentRails instances. The chain-specific configuration (Circle's TokenMessengerV2 and native
/// USDC) is fixed as factory immutables, so the registry guarantees both the bytecode and the
/// wiring of every module it lists — not just that the bytecode matches. Getting this wiring wrong
/// is what makes a bridge module dangerous, so pinning it at factory deployment removes it from the
/// per-module deployment surface. Deploy one factory per chain. Supports both CREATE (simple) and
/// CREATE2 (deterministic) deployment.
///
/// Deployment is permissionless, unlike {ICowSwapModuleFactory}. The registry here is keyed only
/// by module address and carries no per-PaymentRails index, so a deployment by a stranger asserts
/// nothing about any PaymentRails and cannot be surfaced under a victim's entry. Every module is
/// wired identically and holds no privileged role: the destination domain, mint recipient and fee
/// bound all come from the per-token params the PaymentRails owner sets via `configureToken`.
interface ICCTPBridgeModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new CCTPBridgeModule instance is deployed.
    /// @param module The address of the deployed CCTPBridgeModule contract.
    /// @param deployer The address that called the factory.
    event CCTPBridgeModuleCreated(address indexed module, address indexed deployer);

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new CCTPBridgeModule instance using CREATE.
    /// @dev Emits a {CCTPBridgeModuleCreated} event. The module is wired to this factory's
    /// {tokenMessenger} and {usdc}.
    /// @return module The address of the deployed CCTPBridgeModule contract.
    function create() external returns (address module);

    /// @notice Deploy a new CCTPBridgeModule instance using CREATE2 for deterministic addressing.
    /// @dev Emits a {CCTPBridgeModuleCreated} event. The deployment address can be predicted off-chain
    /// via {predictDeterministicAddress}. Reverts if a contract already exists at the predicted address.
    ///
    /// Requirements:
    /// - `salt` must not have been used before on this factory
    ///
    /// @param salt The salt for CREATE2 address derivation.
    /// @return module The address of the deployed CCTPBridgeModule contract.
    function createDeterministic(bytes32 salt) external returns (address module);

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Circle's TokenMessengerV2 every deployed module is wired to.
    /// @return The TokenMessengerV2 address on this chain.
    function tokenMessenger() external view returns (address);

    /// @notice The native USDC every deployed module is wired to.
    /// @return The USDC address on this chain.
    function usdc() external view returns (address);

    /// @notice Predict the address of a deterministic deployment.
    /// @dev All constructor arguments are factory immutables, so the address depends only on the salt.
    /// A caller who broadcasts a salt can have it taken by anyone; treat a predicted address as
    /// reserved only once {isDeployedModule} confirms it. Any module that does land there carries this
    /// factory's wiring, so a taken salt costs a deployment, not safety.
    /// @param salt The salt that would be passed to {createDeterministic}.
    /// @return predicted The address where the CCTPBridgeModule would be deployed.
    function predictDeterministicAddress(bytes32 salt) external view returns (address predicted);

    /// @notice Check whether an address was deployed by this factory.
    /// @param module The address to check.
    /// @return isModule True if the address was deployed by this factory.
    function isDeployedModule(address module) external view returns (bool isModule);

    /// @notice Return all CCTPBridgeModule instances deployed by this factory.
    /// @dev May be expensive for off-chain calls if the array is very large. Prefer event indexing at scale.
    /// @return modules Array of deployed CCTPBridgeModule addresses.
    function getDeployedModules() external view returns (address[] memory modules);

    /// @notice Return the total number of CCTPBridgeModule instances deployed by this factory.
    /// @return count Number of deployed modules.
    function getModuleCount() external view returns (uint256 count);
}
