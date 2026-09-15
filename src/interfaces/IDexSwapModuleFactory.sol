// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IDexSwapModuleFactory
/// @notice Interface for the factory that deploys and tracks DexSwapModule instances.
/// @dev DexSwapModule is stateless, so a single deployment can be shared by any number of
/// PaymentRails instances. The chain-specific configuration (Uniswap V3 router, L2 sequencer
/// uptime feed and grace period) is fixed as factory immutables, so the registry guarantees both
/// the bytecode and the wiring of every module it lists — not just that the bytecode matches.
/// Deploy one factory per chain. Supports both CREATE (simple) and CREATE2 (deterministic)
/// deployment.
///
/// Deployment is permissionless, unlike {ICowSwapModuleFactory}. The registry here is keyed only
/// by module address and carries no per-PaymentRails index, so a deployment by a stranger asserts
/// nothing about any PaymentRails and cannot be surfaced under a victim's entry. Every module is
/// wired identically and holds no privileged role: the swap route, oracle feeds and slippage bound
/// all come from the per-token params the PaymentRails owner sets via `configureToken`.
interface IDexSwapModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new DexSwapModule instance is deployed.
    /// @param module The address of the deployed DexSwapModule contract.
    /// @param deployer The address that called the factory.
    event DexSwapModuleCreated(address indexed module, address indexed deployer);

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new DexSwapModule instance using CREATE.
    /// @dev Emits a {DexSwapModuleCreated} event. The module is wired to this factory's
    /// {router}, {sequencerUptimeFeed} and {sequencerGracePeriod}.
    /// @return module The address of the deployed DexSwapModule contract.
    function create() external returns (address module);

    /// @notice Deploy a new DexSwapModule instance using CREATE2 for deterministic addressing.
    /// @dev Emits a {DexSwapModuleCreated} event. The deployment address can be predicted off-chain
    /// via {predictDeterministicAddress}. Reverts if a contract already exists at the predicted address.
    ///
    /// Requirements:
    /// - `salt` must not have been used before on this factory
    ///
    /// @param salt The salt for CREATE2 address derivation.
    /// @return module The address of the deployed DexSwapModule contract.
    function createDeterministic(bytes32 salt) external returns (address module);

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The Uniswap V3 SwapRouter every deployed module is wired to.
    /// @return The SwapRouter address.
    function router() external view returns (address);

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
    /// @dev All constructor arguments are factory immutables, so the address depends only on the salt.
    /// A caller who broadcasts a salt can have it taken by anyone; treat a predicted address as
    /// reserved only once {isDeployedModule} confirms it. Any module that does land there carries this
    /// factory's wiring, so a taken salt costs a deployment, not safety.
    /// @param salt The salt that would be passed to {createDeterministic}.
    /// @return predicted The address where the DexSwapModule would be deployed.
    function predictDeterministicAddress(bytes32 salt) external view returns (address predicted);

    /// @notice Check whether an address was deployed by this factory.
    /// @param module The address to check.
    /// @return isModule True if the address was deployed by this factory.
    function isDeployedModule(address module) external view returns (bool isModule);

    /// @notice Return all DexSwapModule instances deployed by this factory.
    /// @dev May be expensive for off-chain calls if the array is very large. Prefer event indexing at scale.
    /// @return modules Array of deployed DexSwapModule addresses.
    function getDeployedModules() external view returns (address[] memory modules);

    /// @notice Return the total number of DexSwapModule instances deployed by this factory.
    /// @return count Number of deployed modules.
    function getModuleCount() external view returns (uint256 count);
}
