// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console2 } from "forge-std/src/Script.sol";
import { CowSwapModuleFactory } from "../../../src/modules/swaps/CowSwapModuleFactory.sol";

import { BaseScript } from "../Base.s.sol";

/// @title DeployCowSwapModuleFactory
/// @author Credit Cooperative
/// @notice Deploys the CowSwapModuleFactory contract. Run once per chain; use the factory to deploy
///         a dedicated CowSwapModule per PaymentRails instance.
///
///      Usage:
///        source .env && forge script scripts/solidity/deploy/DeployCowSwapModuleFactory.s.sol \
///          --sig "run(address,uint256)" <SEQUENCER_FEED_OR_0x0> <GRACE_PERIOD> \
///          --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract DeployCowSwapModuleFactory is BaseScript {
    address internal constant GPV2_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;

    function run(
        address _sequencerUptimeFeed,
        uint256 _sequencerGracePeriod
    )
        public
        broadcast
        returns (CowSwapModuleFactory factory)
    {
        factory = new CowSwapModuleFactory(GPV2_SETTLEMENT, _sequencerUptimeFeed, _sequencerGracePeriod);

        console2.log("=============================================================");
        console2.log("  DeployCowSwapModuleFactory - Complete");
        console2.log("=============================================================");
        console2.log("CowSwapModuleFactory:", address(factory));
        console2.log("GPv2Settlement:      ", GPV2_SETTLEMENT);
        console2.log("SequencerUptimeFeed: ", _sequencerUptimeFeed);
        console2.log("SequencerGracePeriod:", _sequencerGracePeriod);
        console2.log("");
        console2.log("Save to .env:");
        console2.log("  COW_SWAP_MODULE_FACTORY_ADDRESS=%s", vm.toString(address(factory)));
        console2.log("");
        console2.log("Then deploy a module per PaymentRails:");
        console2.log("  cast send $COW_SWAP_MODULE_FACTORY_ADDRESS 'create(address,address)' <OWNER> <PAYMENT_RAILS>");
        console2.log("=============================================================");
    }
}
