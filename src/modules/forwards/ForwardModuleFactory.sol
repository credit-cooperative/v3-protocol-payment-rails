// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IForwardModuleFactory } from "../../interfaces/IForwardModuleFactory.sol";
import { ForwardModule } from "./ForwardModule.sol";

/// @title ForwardModuleFactory
/// @author Credit Cooperative
/// @notice See the documentation in {IForwardModuleFactory}.
contract ForwardModuleFactory is IForwardModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Array of all deployed ForwardModule instances.
    address[] private _deployedModules;

    /// @dev Maps deployed module addresses to true for O(1) lookups.
    mapping(address module => bool deployed) private _isDeployedModule;

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IForwardModuleFactory
    function create() external returns (address module) {
        // Interactions: Deploy a new ForwardModule.
        module = address(new ForwardModule());

        // Effects: Register in the on-chain registry.
        _register(module);
    }

    /// @inheritdoc IForwardModuleFactory
    function createDeterministic(bytes32 salt) external returns (address module) {
        // Interactions: Deploy a new ForwardModule with a deterministic address.
        module = address(new ForwardModule{ salt: salt }());

        // Effects: Register in the on-chain registry.
        _register(module);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IForwardModuleFactory
    function predictDeterministicAddress(bytes32 salt) external view returns (address predicted) {
        bytes32 bytecodeHash = keccak256(type(ForwardModule).creationCode);
        predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
    }

    /// @inheritdoc IForwardModuleFactory
    function isDeployedModule(address module) external view returns (bool) {
        return _isDeployedModule[module];
    }

    /// @inheritdoc IForwardModuleFactory
    function getDeployedModules() external view returns (address[] memory) {
        return _deployedModules;
    }

    /// @inheritdoc IForwardModuleFactory
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

        emit ForwardModuleCreated(module, msg.sender);
    }
}
