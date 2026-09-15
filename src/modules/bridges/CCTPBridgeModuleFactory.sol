// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { ICCTPBridgeModuleFactory } from "../../interfaces/ICCTPBridgeModuleFactory.sol";
import { CCTPBridgeModule } from "./CCTPBridgeModule.sol";
import { Errors } from "../../libraries/Errors.sol";

/// @title CCTPBridgeModuleFactory
/// @author Credit Cooperative
/// @notice See the documentation in {ICCTPBridgeModuleFactory}.
contract CCTPBridgeModuleFactory is ICCTPBridgeModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                IMMUTABLE STATE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICCTPBridgeModuleFactory
    address public immutable override tokenMessenger;

    /// @inheritdoc ICCTPBridgeModuleFactory
    address public immutable override usdc;

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Array of all deployed CCTPBridgeModule instances.
    address[] private _deployedModules;

    /// @dev Maps deployed module addresses to true for O(1) lookups.
    mapping(address module => bool deployed) private _isDeployedModule;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Chain-specific configuration is fixed at factory deployment so the registry
    /// guarantees the wiring of every module it lists, not just the bytecode.
    /// @param _tokenMessenger Circle's TokenMessengerV2 on this chain (must be a contract).
    /// @param _usdc Native USDC on this chain (must be a contract).
    constructor(address _tokenMessenger, address _usdc) {
        if (_tokenMessenger == address(0)) {
            revert Errors.CCTPBridgeModuleFactory_ZeroTokenMessenger();
        }
        // Modules burn real USDC through these two addresses; a typo pointing at an EOA would
        // only surface at bridge time, with funds already pulled from the PaymentRails.
        if (_tokenMessenger.code.length == 0) {
            revert Errors.CCTPBridgeModuleFactory_TokenMessengerNotContract(_tokenMessenger);
        }
        if (_usdc == address(0)) {
            revert Errors.CCTPBridgeModuleFactory_ZeroUSDC();
        }
        if (_usdc.code.length == 0) {
            revert Errors.CCTPBridgeModuleFactory_USDCNotContract(_usdc);
        }

        tokenMessenger = _tokenMessenger;
        usdc = _usdc;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICCTPBridgeModuleFactory
    function create() external returns (address module) {
        // Interactions: Deploy a new CCTPBridgeModule wired to the factory chain config.
        module = address(new CCTPBridgeModule(tokenMessenger, usdc));

        // Effects: Register in the on-chain registry.
        _register(module);
    }

    /// @inheritdoc ICCTPBridgeModuleFactory
    function createDeterministic(bytes32 salt) external returns (address module) {
        // Interactions: Deploy a new CCTPBridgeModule with a deterministic address.
        module = address(new CCTPBridgeModule{ salt: salt }(tokenMessenger, usdc));

        // Effects: Register in the on-chain registry.
        _register(module);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICCTPBridgeModuleFactory
    function predictDeterministicAddress(bytes32 salt) external view returns (address predicted) {
        bytes32 bytecodeHash =
            keccak256(abi.encodePacked(type(CCTPBridgeModule).creationCode, abi.encode(tokenMessenger, usdc)));
        predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
    }

    /// @inheritdoc ICCTPBridgeModuleFactory
    function isDeployedModule(address module) external view returns (bool) {
        return _isDeployedModule[module];
    }

    /// @inheritdoc ICCTPBridgeModuleFactory
    function getDeployedModules() external view returns (address[] memory) {
        return _deployedModules;
    }

    /// @inheritdoc ICCTPBridgeModuleFactory
    function getModuleCount() external view returns (uint256) {
        return _deployedModules.length;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Registers a newly deployed module in the on-chain registry and emits the creation event.
    function _register(address module) private {
        _deployedModules.push(module);
        _isDeployedModule[module] = true;

        emit CCTPBridgeModuleCreated(module, msg.sender);
    }
}
