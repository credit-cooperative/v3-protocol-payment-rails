// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { ICowSwapModuleFactory } from "../../interfaces/ICowSwapModuleFactory.sol";
import { CowSwapModule } from "./CowSwapModule.sol";
import { Errors } from "../../libraries/Errors.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

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
        // address(0) is the L1 profile and stays valid. A non-zero EOA is always a misconfiguration:
        // the module's oracle read would hit the extcodesize check and revert, so every module this
        // factory deploys could never place an order. The wiring is immutable, so a typo caught here
        // costs a factory redeployment instead of the factory plus every module under it.
        if (_sequencerUptimeFeed != address(0) && _sequencerUptimeFeed.code.length == 0) {
            revert Errors.CowSwapModuleFactory_SequencerFeedNotContract(_sequencerUptimeFeed);
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
    function _checkCreateParams(address owner, address paymentRails) private view {
        // Zero owner would brick the module: renounceOwnership is disabled and no one could cancel orders.
        if (owner == address(0)) {
            revert Errors.CowSwapModuleFactory_ZeroOwner();
        }
        // Zero paymentRails would make the module unusable: execute() only accepts the wired caller.
        if (paymentRails == address(0)) {
            revert Errors.CowSwapModuleFactory_ZeroPaymentRails();
        }

        _checkPaymentRailsOwner(paymentRails);
    }

    /// @dev Reverts unless the caller is the current owner of `paymentRails`.
    ///
    /// The registry indexes modules by the PaymentRails they are wired to, and integrators read
    /// {getModulesForPaymentRails} to discover "the" module for an instance. Without this check any
    /// address could call {create} with a victim's PaymentRails and an attacker-controlled `owner`,
    /// planting an attacker-owned module in the victim's registry entry — the victim would then see
    /// a module that is factory-deployed, correctly wired, and reported under their own PaymentRails,
    /// while the attacker holds `cancelOrder` rights over it. Requiring the PaymentRails owner to be
    /// the caller makes every registry entry an assertion that the instance's own owner authorized it.
    ///
    /// The owner is read at call time, so an Ownable2Step transfer moves the right to register modules
    /// along with ownership: only the accepted (current) owner qualifies, never the pending one.
    function _checkPaymentRailsOwner(address paymentRails) private view {
        // An EOA cannot own anything, and its staticcall would succeed with empty returndata.
        if (paymentRails.code.length == 0) {
            revert Errors.CowSwapModuleFactory_PaymentRailsNotContract(paymentRails);
        }

        // Low-level call rather than `try`: a contract that returns malformed data for `owner()`
        // must surface as an explicit lookup failure, not as an uncatchable decoding revert.
        (bool success, bytes memory returndata) =
            paymentRails.staticcall(abi.encodeWithSelector(Ownable.owner.selector));
        if (!success || returndata.length != 32) {
            revert Errors.CowSwapModuleFactory_OwnerLookupFailed(paymentRails);
        }

        // Decode as a raw word, not as `address`: a 32-byte answer is not necessarily canonical ABI
        // padding, and `abi.decode(..., (address))` reverts on dirty upper bits with empty revert data
        // — defeating the explicit lookup failure promised above. Validate the padding ourselves.
        bytes32 ownerWord = abi.decode(returndata, (bytes32));
        if (uint256(ownerWord) > type(uint160).max) {
            revert Errors.CowSwapModuleFactory_OwnerLookupFailed(paymentRails);
        }

        address paymentRailsOwner = address(uint160(uint256(ownerWord)));
        if (msg.sender != paymentRailsOwner) {
            revert Errors.CowSwapModuleFactory_CallerNotPaymentRailsOwner(msg.sender, paymentRailsOwner);
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
