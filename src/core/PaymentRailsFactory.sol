// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IPaymentRailsFactory } from "../interfaces/IPaymentRailsFactory.sol";
import { PaymentRails } from "./PaymentRails.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title PaymentRailsFactory
/// @author Credit Cooperative
/// @notice See the documentation in {IPaymentRailsFactory}.
/// @dev Creation is restricted to the owner and owner-approved factory operators so the on-chain
/// registry only ever lists instances this organization deployed. Both creation paths are gated:
/// leaving either one open would let anyone register an instance and defeat the restriction.
/// Operators can only create; operator and ownership management stay with the owner.
contract PaymentRailsFactory is IPaymentRailsFactory, Ownable2Step {
    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Array of all deployed PaymentRails instances.
    address[] private _deployedInstances;

    /// @dev Maps deployed instance addresses to true for O(1) lookups.
    mapping(address instance => bool deployed) private _isDeployedInstance;

    /// @inheritdoc IPaymentRailsFactory
    mapping(address operator => bool approved) public override factoryOperators;

    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param initialOwner Address allowed to create instances and to approve factory operators.
    /// Taken as an argument, not `msg.sender`, so the deployer never holds the role and no handover is
    /// required. No operator is approved at construction.
    constructor(address initialOwner) Ownable(initialOwner) { }

    /*//////////////////////////////////////////////////////////////////////////
                                OWNERSHIP
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Disables renounceOwnership(): renouncing would freeze the operator set -- no one could
    /// revoke a compromised operator or approve a new one -- and with no operator approved would
    /// leave both creation paths permanently uncallable, bricking the factory.
    function renounceOwnership() public pure override {
        revert Errors.PaymentRailsFactory_OwnershipCannotBeRenounced();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentRailsFactory
    function setFactoryOperator(address operator, bool approved) external onlyOwner returns (bool) {
        // Checks: address(0) can never be msg.sender, so approving it is always a mistake.
        if (operator == address(0)) {
            revert Errors.PaymentRailsFactory_ZeroOperator();
        }

        // Effects: Idempotent by design; an unchanged value still emits so the log mirrors every owner action.
        factoryOperators[operator] = approved;

        emit FactoryOperatorSet(msg.sender, operator, approved);
        return true;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentRailsFactory
    function create(address railsOwner) external onlyOwnerOrFactoryOperator returns (address paymentRails) {
        // Checks: Zero owner would lock the PaymentRails since renounceOwnership is disabled.
        if (railsOwner == address(0)) {
            revert Errors.PaymentRailsFactory_ZeroOwner();
        }

        // Interactions: Deploy new PaymentRails with railsOwner.
        paymentRails = address(new PaymentRails(railsOwner));

        // Effects: Register in the on-chain registry.
        _register(paymentRails, railsOwner);
    }

    /// @inheritdoc IPaymentRailsFactory
    function createDeterministic(
        address railsOwner,
        bytes32 salt
    )
        external
        onlyOwnerOrFactoryOperator
        returns (address paymentRails)
    {
        // Checks: Zero owner would lock the PaymentRails since renounceOwnership is disabled.
        if (railsOwner == address(0)) {
            revert Errors.PaymentRailsFactory_ZeroOwner();
        }

        // NOTE: the salt is not bound to the caller, so another authorized caller (owner or operator)
        // can submit the same arguments and salt first. The original tx then reverts while the same
        // contract lands at the same address: griefing only. Callers should check the predicted
        // address for code before sending.
        // Interactions: Deploy new PaymentRails with deterministic address.
        paymentRails = address(new PaymentRails{ salt: salt }(railsOwner));

        // Effects: Register in the on-chain registry.
        _register(paymentRails, railsOwner);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentRailsFactory
    function predictDeterministicAddress(address railsOwner, bytes32 salt) external view returns (address predicted) {
        bytes32 bytecodeHash = keccak256(abi.encodePacked(type(PaymentRails).creationCode, abi.encode(railsOwner)));
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
    function _register(address paymentRails, address railsOwner) private {
        _deployedInstances.push(paymentRails);
        _isDeployedInstance[paymentRails] = true;

        emit PaymentRailsCreated(paymentRails, railsOwner);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Restricts creation to the factory owner or an approved factory operator.
    modifier onlyOwnerOrFactoryOperator() {
        if (msg.sender != owner() && !factoryOperators[msg.sender]) {
            revert Errors.PaymentRailsFactory_NotOwnerOrOperator(msg.sender);
        }
        _;
    }
}
