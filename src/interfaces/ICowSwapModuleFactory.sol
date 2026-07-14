// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title ICowSwapModuleFactory
/// @notice Interface for the factory that deploys and tracks CowSwapModule instances.
/// @dev CowSwapModule is stateful (tracks pending orders, immutable `paymentRails`), so each
/// PaymentRails needs its own dedicated module instance. This factory deploys them with the
/// chain-specific configuration (GPv2Settlement, sequencer feed) fixed as factory immutables,
/// so the registry guarantees both bytecode and wiring of every registered module. Supports
/// both CREATE (simple) and CREATE2 (deterministic) deployment.
interface ICowSwapModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new CowSwapModule instance is deployed.
    /// @param module The address of the deployed CowSwapModule contract.
    /// @param paymentRails The PaymentRails instance the module is wired to.
    /// @param owner The initial owner of the CowSwapModule contract.
    event CowSwapModuleCreated(address indexed module, address indexed paymentRails, address indexed owner);

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new CowSwapModule instance using CREATE.
    /// @dev Emits a {CowSwapModuleCreated} event.
    ///
    /// Requirements:
    /// - `owner` must not be `address(0)`
    /// - `paymentRails` must not be `address(0)`
    ///
    /// @param owner The initial owner of the CowSwapModule (can cancel orders).
    /// @param paymentRails The PaymentRails instance authorized to call the module's execute().
    /// @return module The address of the deployed CowSwapModule contract.
    function create(address owner, address paymentRails) external returns (address module);

    /// @notice Deploy a new CowSwapModule instance using CREATE2 for deterministic addressing.
    /// @dev Emits a {CowSwapModuleCreated} event. The deployment address can be predicted off-chain
    /// via {predictDeterministicAddress}. Reverts if a contract already exists at the predicted address.
    ///
    /// Requirements:
    /// - `owner` must not be `address(0)`
    /// - `paymentRails` must not be `address(0)`
    /// - The `(owner, paymentRails, salt)` combination must not have been used before
    ///
    /// @param owner The initial owner of the CowSwapModule (can cancel orders).
    /// @param paymentRails The PaymentRails instance authorized to call the module's execute().
    /// @param salt The salt for CREATE2 address derivation.
    /// @return module The address of the deployed CowSwapModule contract.
    function createDeterministic(address owner, address paymentRails, bytes32 salt) external returns (address module);

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The GPv2Settlement contract every deployed module is wired to.
    /// @return The GPv2Settlement address.
    function cowSettlement() external view returns (address);

    /// @notice The Chainlink L2 sequencer uptime feed passed to every deployed module.
    /// @return The sequencer uptime feed address; `address(0)` on L1.
    function sequencerUptimeFeed() external view returns (address);

    /// @notice The sequencer grace period passed to every deployed module.
    /// @return The grace period, denoted in seconds.
    function sequencerGracePeriod() external view returns (uint256);

    /// @notice Predict the address of a deterministic deployment.
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
    /// @dev Multiple modules per PaymentRails are possible (e.g. redeployments); the last entry
    /// is the most recently deployed.
    /// @param paymentRails The PaymentRails instance to look up.
    /// @return modules Array of CowSwapModule addresses wired to `paymentRails`.
    function getModulesForPaymentRails(address paymentRails) external view returns (address[] memory modules);
}
