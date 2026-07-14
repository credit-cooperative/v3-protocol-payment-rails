// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { ICowSwapModuleFactory } from "../../interfaces/ICowSwapModuleFactory.sol";
import { CowSwapModule } from "./CowSwapModule.sol";
import { Errors } from "../../libraries/Errors.sol";

/// @title CowSwapModuleFactory
/// @author Credit Cooperative
/// @notice See the documentation in {ICowSwapModuleFactory}.
contract CowSwapModuleFactory is ICowSwapModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                IMMUTABLE STATE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICowSwapModuleFactory
    address public immutable override cowSettlement;

    /// @inheritdoc ICowSwapModuleFactory
    address public immutable override sequencerUptimeFeed;

    /// @inheritdoc ICowSwapModuleFactory
    uint256 public immutable override sequencerGracePeriod;

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Array of all deployed CowSwapModule instances.
    address[] private _deployedModules;

    /// @dev Maps deployed module addresses to true for O(1) lookups.
    mapping(address module => bool deployed) private _isDeployedModule;

    /// @dev Maps a PaymentRails to all modules deployed for it.
    mapping(address paymentRails => address[] modules) private _modulesByPaymentRails;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Chain-specific configuration is fixed at factory deployment so the registry
    /// guarantees the wiring of every module it lists, not just the bytecode.
    /// @param _cowSettlement GPv2Settlement contract address.
    /// @param _sequencerUptimeFeed Chainlink L2 sequencer uptime feed; address(0) on L1.
    /// @param _sequencerGracePeriod Seconds after sequencer recovery before trusting oracles.
    constructor(address _cowSettlement, address _sequencerUptimeFeed, uint256 _sequencerGracePeriod) {
        if (_cowSettlement == address(0)) {
            revert Errors.CowSwapModuleFactory_ZeroCowSettlement();
        }
        // The module constructor calls domainSeparator() and vaultRelayer() on this address;
        // rejecting EOAs here fails fast at factory deployment instead of on every create().
        if (_cowSettlement.code.length == 0) {
            revert Errors.CowSwapModuleFactory_SettlementNotContract(_cowSettlement);
        }

        cowSettlement = _cowSettlement;
        sequencerUptimeFeed = _sequencerUptimeFeed;
        sequencerGracePeriod = _sequencerGracePeriod;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICowSwapModuleFactory
    function create(address owner, address paymentRails) external returns (address module) {
        // Checks: Validate the per-instance parameters.
        _checkCreateParams(owner, paymentRails);

        // Interactions: Deploy new CowSwapModule wired to the PaymentRails.
        module =
            address(new CowSwapModule(cowSettlement, owner, paymentRails, sequencerUptimeFeed, sequencerGracePeriod));

        // Effects: Register in the on-chain registry.
        _register(module, paymentRails, owner);
    }

    /// @inheritdoc ICowSwapModuleFactory
    function createDeterministic(address owner, address paymentRails, bytes32 salt) external returns (address module) {
        // Checks: Validate the per-instance parameters.
        _checkCreateParams(owner, paymentRails);

        // Interactions: Deploy new CowSwapModule with deterministic address.
        module = address(
            new CowSwapModule{ salt: salt }(
                cowSettlement, owner, paymentRails, sequencerUptimeFeed, sequencerGracePeriod
            )
        );

        // Effects: Register in the on-chain registry.
        _register(module, paymentRails, owner);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICowSwapModuleFactory
    function predictDeterministicAddress(
        address owner,
        address paymentRails,
        bytes32 salt
    )
        external
        view
        returns (address predicted)
    {
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(CowSwapModule).creationCode,
                abi.encode(cowSettlement, owner, paymentRails, sequencerUptimeFeed, sequencerGracePeriod)
            )
        );
        predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
    }

    /// @inheritdoc ICowSwapModuleFactory
    function isDeployedModule(address module) external view returns (bool) {
        return _isDeployedModule[module];
    }

    /// @inheritdoc ICowSwapModuleFactory
    function getDeployedModules() external view returns (address[] memory) {
        return _deployedModules;
    }

    /// @inheritdoc ICowSwapModuleFactory
    function getModuleCount() external view returns (uint256) {
        return _deployedModules.length;
    }

    /// @inheritdoc ICowSwapModuleFactory
    function getModulesForPaymentRails(address paymentRails) external view returns (address[] memory) {
        return _modulesByPaymentRails[paymentRails];
    }

    /*//////////////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Validates the per-instance deployment parameters shared by both create functions.
    function _checkCreateParams(address owner, address paymentRails) private pure {
        // Zero owner would brick the module: renounceOwnership is disabled and no one could cancel orders.
        if (owner == address(0)) {
            revert Errors.CowSwapModuleFactory_ZeroOwner();
        }
        // Zero paymentRails would make the module unusable: execute() only accepts the wired caller.
        if (paymentRails == address(0)) {
            revert Errors.CowSwapModuleFactory_ZeroPaymentRails();
        }
    }

    /// @dev Registers a newly deployed module in the on-chain registry and emits the creation event.
    function _register(address module, address paymentRails, address owner) private {
        _deployedModules.push(module);
        _isDeployedModule[module] = true;
        _modulesByPaymentRails[paymentRails].push(module);

        emit CowSwapModuleCreated(module, paymentRails, owner);
    }
}
