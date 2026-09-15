// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { DexSwapModuleFactory } from "../../../src/modules/swaps/DexSwapModuleFactory.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployDexSwapModuleFactory
/// @author Credit Cooperative
/// @notice Deploys the DexSwapModuleFactory contract. Run once per chain — the Uniswap V3 router and
///         sequencer configuration are fixed as factory immutables, so every module the factory lists
///         is guaranteed to carry this chain's wiring. DexSwapModule is stateless, so a single module
///         can be shared across PaymentRails instances.
///
///         Pass address(0) for the sequencer feed on L1; on L2s pass the Chainlink sequencer uptime
///         feed with a grace period (3600 is typical).
///
///      Usage:
///        source .env && forge script scripts/solidity/deploy/DeployDexSwapModuleFactory.s.sol \
///          --sig "run(address,address,uint256)" <ROUTER> <SEQUENCER_FEED_OR_0x0> <GRACE_PERIOD> \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployDexSwapModuleFactory is BaseScript {
    function run(
        address _router,
        address _sequencerUptimeFeed,
        uint256 _sequencerGracePeriod
    )
        public
        broadcast
        returns (DexSwapModuleFactory factory)
    {
        factory = new DexSwapModuleFactory(_router, _sequencerUptimeFeed, _sequencerGracePeriod);

        console2.log("=============================================================");
        console2.log("  DeployDexSwapModuleFactory - Complete");
        console2.log("=============================================================");
        console2.log("DexSwapModuleFactory:", address(factory));
        console2.log("UniswapV3 Router:    ", _router);
        console2.log("SequencerUptimeFeed: ", _sequencerUptimeFeed);
        console2.log("SequencerGracePeriod:", _sequencerGracePeriod);
        console2.log("");
        console2.log("Save to .env:");
        console2.log("  DEX_SWAP_MODULE_FACTORY_ADDRESS=%s", vm.toString(address(factory)));
        console2.log("");
        console2.log("Then deploy a module (one shared instance is enough):");
        console2.log("  cast send $DEX_SWAP_MODULE_FACTORY_ADDRESS 'create()'");
        console2.log("=============================================================");
    }
}
