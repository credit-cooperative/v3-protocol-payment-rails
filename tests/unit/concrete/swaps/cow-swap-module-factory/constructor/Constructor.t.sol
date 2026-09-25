// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { CowSwapModuleFactoryBase } from "../CowSwapModuleFactoryBase.t.sol";
import { CowSwapModuleFactory } from "../../../../../../src/modules/swaps/CowSwapModuleFactory.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";

contract Constructor_CowSwapModuleFactory_Test is CowSwapModuleFactoryBase {
    function test_RevertWhen_CowSettlementIsZeroAddress() external {
        vm.expectRevert(Errors.CowSwapModuleFactory_ZeroCowSettlement.selector);
        new CowSwapModuleFactory(owner, address(0), sequencerFeed, DEFAULT_GRACE_PERIOD);
    }

    function test_RevertWhen_CowSettlementHasNoCode() external {
        address eoa = makeAddr("eoaSettlement");
        vm.expectRevert(abi.encodeWithSelector(Errors.CowSwapModuleFactory_SettlementNotContract.selector, eoa));
        new CowSwapModuleFactory(owner, eoa, sequencerFeed, DEFAULT_GRACE_PERIOD);
    }

    function test_RevertWhen_SequencerFeedIsNotContract() external {
        address eoa = makeAddr("eoaSequencerFeed");
        vm.expectRevert(abi.encodeWithSelector(Errors.CowSwapModuleFactory_SequencerFeedNotContract.selector, eoa));
        new CowSwapModuleFactory(owner, address(cowSettlement), eoa, DEFAULT_GRACE_PERIOD);
    }

    /// @dev L1 has no sequencer uptime feed, so address(0) must stay a valid configuration.
    function test_WhenSequencerFeedIsZero_ShouldDeployForL1Profile() external {
        CowSwapModuleFactory newFactory = new CowSwapModuleFactory(owner, address(cowSettlement), address(0), 0);
        assertEq(newFactory.sequencerUptimeFeed(), address(0));
        assertEq(newFactory.sequencerGracePeriod(), 0);
    }

    function test_WhenCowSettlementIsValidContract_ShouldSetCowSettlement() external {
        CowSwapModuleFactory newFactory =
            new CowSwapModuleFactory(owner, address(cowSettlement), sequencerFeed, DEFAULT_GRACE_PERIOD);
        assertEq(newFactory.cowSettlement(), address(cowSettlement));
    }

    function test_WhenCowSettlementIsValidContract_ShouldSetSequencerUptimeFeed() external {
        CowSwapModuleFactory newFactory =
            new CowSwapModuleFactory(owner, address(cowSettlement), sequencerFeed, DEFAULT_GRACE_PERIOD);
        assertEq(newFactory.sequencerUptimeFeed(), sequencerFeed);
    }

    function test_WhenCowSettlementIsValidContract_ShouldSetSequencerGracePeriod() external {
        CowSwapModuleFactory newFactory =
            new CowSwapModuleFactory(owner, address(cowSettlement), sequencerFeed, DEFAULT_GRACE_PERIOD);
        assertEq(newFactory.sequencerGracePeriod(), DEFAULT_GRACE_PERIOD);
    }
}
