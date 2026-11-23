// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IAtumModuleFactory } from "../../../interfaces/IAtumModuleFactory.sol";
import { AtumModule } from "./AtumModule.sol";
import { Errors } from "../../../libraries/Errors.sol";

/// @title AtumModuleFactory
/// @custom:tier contrib
/// @custom:maintainer @atum-labs (security@atumlabs.xyz)
/// @custom:audit-status unaudited
/// @author Credit Cooperative
/// @notice See the documentation in {IAtumModuleFactory}.
/// @dev Creation is restricted to the owner and owner-approved factory operators (Certora L-01:
///      operators extend the trusted set, they do not open creation), mirroring PaymentRailsFactory
///      and CowSwapModuleFactory, so the registry only lists modules this organization deployed and
///      only the owner or an operator can grow it. `paymentRails` only has to be a contract: the
///      factory is not bound to any PaymentRailsFactory, so which rails a module serves is the
///      caller's call.
///      Registration is provenance, not trust: a module deployed with `new AtumModule(...)` rather
///      than through this factory is unaffected, so consumers must verify a module's
///      `owner`/`keeper`/`paymentRails` wiring rather than trusting registry presence, and read
///      `getDeployedModules` offchain (it returns the full array).
contract AtumModuleFactory is IAtumModuleFactory, Ownable2Step {
    /*//////////////////////////////////////////////////////////////////////////
                                IMMUTABLE STATE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAtumModuleFactory
    address public immutable override permit2;

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Array of all deployed AtumModule instances.
    address[] private _deployedModules;

    /// @dev Maps deployed module addresses to true for O(1) lookups.
    mapping(address module => bool deployed) private _isDeployedModule;

    /// @dev Maps a PaymentRails to all modules deployed for it.
    mapping(address paymentRails => address[] modules) private _modulesByPaymentRails;

    /// @inheritdoc IAtumModuleFactory
    mapping(address operator => bool approved) public override factoryOperators;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Permit2 is fixed at factory deployment so the registry guarantees the wiring of every
    /// module it lists, not just the bytecode.
    /// @param initialOwner Address allowed to create modules and to approve factory operators.
    ///        Taken as an argument, not `msg.sender`, so the deployer never holds the role and no handover is
    ///        required. No operator is approved at construction.
    /// @param _permit2 The canonical Permit2 contract on this chain.
    constructor(address initialOwner, address _permit2) Ownable(initialOwner) {
        if (_permit2 == address(0)) {
            revert Errors.AtumModuleFactory_ZeroPermit2();
        }
        // The module constructor rejects a codeless Permit2 itself; checking here fails fast at
        // factory deployment instead of on every create(). This used to be justified by the
        // module calling DOMAIN_SEPARATOR() on the address, which reverted against an EOA as a
        // side effect -- that call was dead state and has been removed, so both checks are now
        // explicit.
        if (_permit2.code.length == 0) {
            revert Errors.AtumModuleFactory_Permit2NotContract(_permit2);
        }

        permit2 = _permit2;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    OWNERSHIP
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Disables renounceOwnership(): renouncing would freeze the operator set -- no one could
    /// revoke a compromised operator or approve a new one -- and with no operator approved would
    /// leave both creation paths permanently uncallable, bricking the factory.
    function renounceOwnership() public pure override {
        revert Errors.AtumModuleFactory_OwnershipCannotBeRenounced();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAtumModuleFactory
    function setFactoryOperator(address operator, bool approved) external onlyOwner returns (bool) {
        // Checks: address(0) can never be msg.sender, so approving it is always a mistake.
        if (operator == address(0)) {
            revert Errors.AtumModuleFactory_ZeroOperator();
        }

        // Effects: Idempotent by design; an unchanged value still emits so the log mirrors every owner action.
        factoryOperators[operator] = approved;

        emit FactoryOperatorSet(msg.sender, operator, approved);
        return true;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAtumModuleFactory
    function create(
        address owner,
        address paymentRails,
        address keeper
    )
        external
        onlyOwnerOrFactoryOperator
        returns (address module)
    {
        // Checks: Validate the per-instance parameters.
        _checkCreateParams(owner, paymentRails, keeper);

        // Interactions: Deploy new AtumModule wired to the PaymentRails.
        module = address(new AtumModule(permit2, paymentRails, owner, keeper));

        // Effects: Register in the on-chain registry.
        _register(module, paymentRails, owner, keeper);
    }

    /// @inheritdoc IAtumModuleFactory
    function createDeterministic(
        address owner,
        address paymentRails,
        address keeper,
        bytes32 salt
    )
        external
        onlyOwnerOrFactoryOperator
        returns (address module)
    {
        // Checks: Validate the per-instance parameters.
        _checkCreateParams(owner, paymentRails, keeper);

        // Interactions: Deploy new AtumModule with deterministic address. The salt is bound to the
        // caller (Certora I-04): the owner and every operator each get a disjoint address space, so
        // authorized callers cannot collide with one another, and an ownership transfer does not
        // hand the old owner's addresses to the new one. The address therefore depends on which
        // account sends the tx: predict with that sender as `deployer`, and have deploy tooling
        // compare the returned address to the prediction.
        module = address(new AtumModule{ salt: _effectiveSalt(msg.sender, salt) }(permit2, paymentRails, owner, keeper));

        // Effects: Register in the on-chain registry.
        _register(module, paymentRails, owner, keeper);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAtumModuleFactory
    function predictDeterministicAddress(
        address deployer,
        address owner,
        address paymentRails,
        address keeper,
        bytes32 salt
    )
        external
        view
        returns (address predicted)
    {
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(type(AtumModule).creationCode, abi.encode(permit2, paymentRails, owner, keeper))
        );
        // `deployer` is explicit rather than msg.sender: prediction is an off-chain read, and the
        // party asking is usually not the party deploying.
        predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), _effectiveSalt(deployer, salt), bytecodeHash)
                    )
                )
            )
        );
    }

    /// @inheritdoc IAtumModuleFactory
    function isDeployedModule(address module) external view returns (bool) {
        return _isDeployedModule[module];
    }

    /// @inheritdoc IAtumModuleFactory
    function getDeployedModules() external view returns (address[] memory) {
        return _deployedModules;
    }

    /// @inheritdoc IAtumModuleFactory
    function getModuleCount() external view returns (uint256) {
        return _deployedModules.length;
    }

    /// @inheritdoc IAtumModuleFactory
    function getModulesForPaymentRails(address paymentRails) external view returns (address[] memory) {
        return _modulesByPaymentRails[paymentRails];
    }

    /*//////////////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Certora I-04: bind the CREATE2 salt to the caller.
    ///
    ///      A bare user-supplied salt lets anyone watch `createDeterministic` in the mempool and
    ///      deploy to the same address first, so the legitimate deployment reverts on a collision.
    ///      Hashing the caller in makes each deployer's address space disjoint (the owner and each
    ///      factory operator separately), which removes the race rather than narrowing it.
    ///
    ///      NOTE: this CHANGES every deterministic address. Anything that precomputed one must be
    ///      recalculated via `predictDeterministicAddress`, which takes the deployer explicitly.
    function _effectiveSalt(address deployer, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(deployer, salt));
    }

    /// @dev Validates the per-instance deployment parameters shared by both create functions.
    ///
    ///      `paymentRails` is only checked for code. Creation is restricted to the owner and approved
    ///      factory operators, so this is not authentication: it catches an authorized caller
    ///      passing an EOA or a typo. The factory is not bound to a PaymentRailsFactory, so a
    ///      PaymentRails from any factory version (or none) is accepted, and one AtumModuleFactory
    ///      does not need redeploying when the rails factory is.
    ///
    ///      `paymentRails.owner()` is deliberately not read: any contract can answer it with a
    ///      chosen address, and the PaymentRails owner does not need to be the caller. The
    ///      factory owner or an operator deploys on the PaymentRails owner's behalf, who then
    ///      decides whether to wire the module via `configureToken`.
    function _checkCreateParams(address owner, address paymentRails, address keeper) private view {
        // Zero owner would brick the module: no one could rotate the keeper or pause.
        if (owner == address(0)) {
            revert Errors.AtumModuleFactory_ZeroOwner();
        }
        // Zero paymentRails would make the module unusable: execute() only accepts the wired caller.
        if (paymentRails == address(0)) {
            revert Errors.AtumModuleFactory_ZeroPaymentRails();
        }
        // Zero keeper is rejected by the module constructor; check here for a clear factory-level error.
        if (keeper == address(0)) {
            revert Errors.AtumModuleFactory_ZeroKeeper();
        }
        // A codeless paymentRails could never call execute(), so the module would be dead on arrival.
        if (paymentRails.code.length == 0) {
            revert Errors.AtumModuleFactory_PaymentRailsNotContract(paymentRails);
        }
    }

    /// @dev Registers a newly deployed module in the on-chain registry and emits the creation event.
    function _register(address module, address paymentRails, address owner, address keeper) private {
        _deployedModules.push(module);
        _isDeployedModule[module] = true;
        _modulesByPaymentRails[paymentRails].push(module);

        emit AtumModuleCreated(module, paymentRails, owner, keeper);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Restricts creation to the factory owner or an approved factory operator.
    modifier onlyOwnerOrFactoryOperator() {
        if (msg.sender != owner() && !factoryOperators[msg.sender]) {
            revert Errors.AtumModuleFactory_NotOwnerOrOperator(msg.sender);
        }
        _;
    }
}
