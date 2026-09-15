// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IDexSwapModuleFactory } from "../../interfaces/IDexSwapModuleFactory.sol";
import { DexSwapModule } from "./DexSwapModule.sol";
import { Errors } from "../../libraries/Errors.sol";

/// @title DexSwapModuleFactory
/// @author Credit Cooperative
/// @notice See the documentation in {IDexSwapModuleFactory}.
contract DexSwapModuleFactory is IDexSwapModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                IMMUTABLE STATE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDexSwapModuleFactory
    address public immutable override router;

    /// @inheritdoc IDexSwapModuleFactory
    address public immutable override sequencerUptimeFeed;

    /// @inheritdoc IDexSwapModuleFactory
    uint256 public immutable override sequencerGracePeriod;

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Array of all deployed DexSwapModule instances.
    address[] private _deployedModules;

    /// @dev Maps deployed module addresses to true for O(1) lookups.
    mapping(address module => bool deployed) private _isDeployedModule;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Chain-specific configuration is fixed at factory deployment so the registry
    /// guarantees the wiring of every module it lists, not just the bytecode.
    /// @param _router Uniswap V3 SwapRouter address (must be a contract).
    /// @param _sequencerUptimeFeed Chainlink L2 sequencer uptime feed; address(0) on L1.
    /// @param _sequencerGracePeriod Seconds after sequencer recovery before trusting oracles.
    constructor(address _router, address _sequencerUptimeFeed, uint256 _sequencerGracePeriod) {
        if (_router == address(0)) {
            revert Errors.DexSwapModuleFactory_ZeroRouter();
        }
        // The module constructor rejects a non-contract router; checking here fails fast at
        // factory deployment instead of on every create().
        if (_router.code.length == 0) {
            revert Errors.DexSwapModuleFactory_RouterNotContract(_router);
        }
        // address(0) is the L1 profile and stays valid. A non-zero EOA is always a misconfiguration:
        // the module's oracle read would hit the extcodesize check and revert, so every module this
        // factory deploys could never execute. The wiring is immutable, so a typo caught here costs a
        // factory redeployment instead of the factory plus every module under it.
        if (_sequencerUptimeFeed != address(0) && _sequencerUptimeFeed.code.length == 0) {
            revert Errors.DexSwapModuleFactory_SequencerFeedNotContract(_sequencerUptimeFeed);
        }

        router = _router;
        sequencerUptimeFeed = _sequencerUptimeFeed;
        sequencerGracePeriod = _sequencerGracePeriod;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDexSwapModuleFactory
    function create() external returns (address module) {
        // Interactions: Deploy a new DexSwapModule wired to the factory chain config.
        module = address(new DexSwapModule(router, sequencerUptimeFeed, sequencerGracePeriod));

        // Effects: Register in the on-chain registry.
        _register(module);
    }

    /// @inheritdoc IDexSwapModuleFactory
    function createDeterministic(bytes32 salt) external returns (address module) {
        // Interactions: Deploy a new DexSwapModule with a deterministic address.
        module = address(new DexSwapModule{ salt: salt }(router, sequencerUptimeFeed, sequencerGracePeriod));

        // Effects: Register in the on-chain registry.
        _register(module);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDexSwapModuleFactory
    function predictDeterministicAddress(bytes32 salt) external view returns (address predicted) {
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(DexSwapModule).creationCode, abi.encode(router, sequencerUptimeFeed, sequencerGracePeriod)
            )
        );
        predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
    }

    /// @inheritdoc IDexSwapModuleFactory
    function isDeployedModule(address module) external view returns (bool) {
        return _isDeployedModule[module];
    }

    /// @inheritdoc IDexSwapModuleFactory
    function getDeployedModules() external view returns (address[] memory) {
        return _deployedModules;
    }

    /// @inheritdoc IDexSwapModuleFactory
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

        emit DexSwapModuleCreated(module, msg.sender);
    }
}
