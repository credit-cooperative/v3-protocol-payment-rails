// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IPaymentRailsFactory } from "../interfaces/IPaymentRailsFactory.sol";
import { PaymentRails } from "./PaymentRails.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title PaymentRailsFactory
/// @author Credit Cooperative
/// @notice See the documentation in {IPaymentRailsFactory}.
contract PaymentRailsFactory is IPaymentRailsFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Array of all deployed PaymentRails instances.
    address[] private _deployedInstances;

    /// @dev Maps deployed instance addresses to true for O(1) lookups.
    mapping(address instance => bool deployed) private _isDeployedInstance;

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentRailsFactory
    function create(address owner) external returns (address paymentRails) {
        // Checks: Zero owner would lock the PaymentRails since renounceOwnership is disabled.
        if (owner == address(0)) {
            revert Errors.PaymentRailsFactory_ZeroOwner();
        }

        // Interactions: Deploy new PaymentRails with owner.
        paymentRails = address(new PaymentRails(owner));

        // Effects: Register in the on-chain registry.
        _register(paymentRails, owner);
    }

    /// @inheritdoc IPaymentRailsFactory
    function createDeterministic(address owner, bytes32 salt) external returns (address paymentRails) {
        // Checks: Zero owner would lock the PaymentRails since renounceOwnership is disabled.
        if (owner == address(0)) {
            revert Errors.PaymentRailsFactory_ZeroOwner();
        }

        // Interactions: Deploy new PaymentRails with deterministic address.
        paymentRails = address(new PaymentRails{ salt: salt }(owner));

        // Effects: Register in the on-chain registry.
        _register(paymentRails, owner);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentRailsFactory
    function predictDeterministicAddress(address owner, bytes32 salt) external view returns (address predicted) {
        bytes32 bytecodeHash = keccak256(abi.encodePacked(type(PaymentRails).creationCode, abi.encode(owner)));
        predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
    }

    /// @inheritdoc IPaymentRailsFactory
    function isDeployedInstance(address instance) external view returns (bool) {
        return _isDeployedInstance[instance];
    }

    /// @inheritdoc IPaymentRailsFactory
    function getDeployedInstances() external view returns (address[] memory) {
        return _deployedInstances;
    }

    /// @inheritdoc IPaymentRailsFactory
    function getInstanceCount() external view returns (uint256) {
        return _deployedInstances.length;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Registers a newly deployed instance in the on-chain registry and emits the creation event.
    function _register(address paymentRails, address owner) private {
        _deployedInstances.push(paymentRails);
        _isDeployedInstance[paymentRails] = true;

        emit PaymentRailsCreated(paymentRails, owner);
    }
}
