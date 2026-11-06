// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IBraleModuleFactory } from "../../interfaces/IBraleModuleFactory.sol";
import { BraleModule } from "./BraleModule.sol";
import { Errors } from "../../libraries/Errors.sol";

/// @title BraleModuleFactory
/// @author Credit Cooperative
/// @notice See the documentation in {IBraleModuleFactory}.
/// @dev Creation is owner-gated, mirroring PaymentRailsFactory and AtumModuleFactory, so the registry only
///      lists modules this organization deployed and only the owner can grow it. `paymentRails` only has to
///      be a contract. Registration is provenance, not trust: a module deployed with
///      `new BraleModule(...)` rather than through this factory is unaffected, so consumers must verify a
///      module's `owner`/`paymentRails` wiring rather than trusting registry presence. The off-chain
///      redemption service should allowlist emitters from this registry and verify `paymentRails()`.
contract BraleModuleFactory is IBraleModuleFactory, Ownable2Step {
    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Array of all deployed BraleModule instances.
    address[] private _deployedModules;

    /// @dev Maps deployed module addresses to true for O(1) lookups.
    mapping(address module => bool deployed) private _isDeployedModule;

    /// @dev Maps a PaymentRails to all modules deployed for it.
    mapping(address paymentRails => address[] modules) private _modulesByPaymentRails;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param initialOwner Address allowed to create modules. Taken as an argument, not
    ///        `msg.sender`, so the deployer never holds the role and no handover is required.
    constructor(address initialOwner) Ownable(initialOwner) { }

    /*//////////////////////////////////////////////////////////////////////////
                                    OWNERSHIP
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Disables renounceOwnership(): renouncing would leave both creation paths permanently
    /// uncallable, bricking the factory.
    function renounceOwnership() public pure override {
        revert Errors.BraleModuleFactory_OwnershipCannotBeRenounced();
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBraleModuleFactory
    function create(address owner, address paymentRails) external onlyOwner returns (address module) {
        // Checks: Validate the per-instance parameters.
        _checkCreateParams(owner, paymentRails);

        // Interactions: Deploy new BraleModule wired to the PaymentRails.
        module = address(new BraleModule(paymentRails, owner));

        // Effects: Register in the on-chain registry.
        _register(module, paymentRails, owner);
    }

    /// @inheritdoc IBraleModuleFactory
    function createDeterministic(
        address owner,
        address paymentRails,
        bytes32 salt
    )
        external
        onlyOwner
        returns (address module)
    {
        // Checks: Validate the per-instance parameters.
        _checkCreateParams(owner, paymentRails);

        // Interactions: Deploy new BraleModule with deterministic address. The salt is bound to the
        // caller (Certora I-04) so each owner's address space is disjoint.
        module = address(new BraleModule{ salt: _effectiveSalt(msg.sender, salt) }(paymentRails, owner));

        // Effects: Register in the on-chain registry.
        _register(module, paymentRails, owner);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBraleModuleFactory
    function predictDeterministicAddress(
        address deployer,
        address owner,
        address paymentRails,
        bytes32 salt
    )
        external
        view
        returns (address predicted)
    {
        // Constructor arg order (paymentRails, owner) must match BraleModule's constructor.
        bytes32 bytecodeHash =
            keccak256(abi.encodePacked(type(BraleModule).creationCode, abi.encode(paymentRails, owner)));
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

    /// @inheritdoc IBraleModuleFactory
    function isDeployedModule(address module) external view returns (bool) {
        return _isDeployedModule[module];
    }

    /// @inheritdoc IBraleModuleFactory
    function getDeployedModules() external view returns (address[] memory) {
        return _deployedModules;
    }

    /// @inheritdoc IBraleModuleFactory
    function getModuleCount() external view returns (uint256) {
        return _deployedModules.length;
    }

    /// @inheritdoc IBraleModuleFactory
    function getModulesForPaymentRails(address paymentRails) external view returns (address[] memory) {
        return _modulesByPaymentRails[paymentRails];
    }

    /*//////////////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Certora I-04: bind the CREATE2 salt to the caller, so a watcher cannot front-run a
    ///      `createDeterministic` call by deploying to the same address first.
    function _effectiveSalt(address deployer, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(deployer, salt));
    }

    /// @dev Validates the per-instance deployment parameters shared by both create functions.
    ///      `paymentRails` is only checked for code. Creation is owner-gated, so this is not
    ///      authentication: it catches the owner passing an EOA or a typo.
    function _checkCreateParams(address owner, address paymentRails) private view {
        // Zero owner would leave the module without anyone able to recover stray tokens.
        if (owner == address(0)) {
            revert Errors.BraleModuleFactory_ZeroOwner();
        }
        // Zero paymentRails would make the module unusable: execute() only accepts the wired caller.
        if (paymentRails == address(0)) {
            revert Errors.BraleModuleFactory_ZeroPaymentRails();
        }
        // A codeless paymentRails could never call execute(), so the module would be dead on arrival.
        if (paymentRails.code.length == 0) {
            revert Errors.BraleModuleFactory_PaymentRailsNotContract(paymentRails);
        }
    }

    /// @dev Registers a newly deployed module in the on-chain registry and emits the creation event.
    function _register(address module, address paymentRails, address owner) private {
        _deployedModules.push(module);
        _isDeployedModule[module] = true;
        _modulesByPaymentRails[paymentRails].push(module);

        emit BraleModuleCreated(module, paymentRails, owner);
    }
}
