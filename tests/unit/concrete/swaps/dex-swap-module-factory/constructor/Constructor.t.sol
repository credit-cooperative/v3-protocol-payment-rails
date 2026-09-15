// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { DexSwapModuleFactoryBase } from "../DexSwapModuleFactoryBase.t.sol";
import { DexSwapModuleFactory } from "../../../../../../src/modules/swaps/DexSwapModuleFactory.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";

contract Constructor_DexSwapModuleFactory_Test is DexSwapModuleFactoryBase {
    function test_RevertWhen_RouterIsZeroAddress() external {
        vm.expectRevert(Errors.DexSwapModuleFactory_ZeroRouter.selector);
        new DexSwapModuleFactory(address(0), sequencerFeed, DEFAULT_GRACE_PERIOD);
    }

    function test_RevertWhen_RouterHasNoCode() external {
        address eoa = makeAddr("eoaRouter");
        vm.expectRevert(abi.encodeWithSelector(Errors.DexSwapModuleFactory_RouterNotContract.selector, eoa));
        new DexSwapModuleFactory(eoa, sequencerFeed, DEFAULT_GRACE_PERIOD);
    }

    function test_RevertWhen_SequencerFeedIsNotContract() external {
        address eoa = makeAddr("eoaSequencerFeed");
        vm.expectRevert(abi.encodeWithSelector(Errors.DexSwapModuleFactory_SequencerFeedNotContract.selector, eoa));
        new DexSwapModuleFactory(address(router), eoa, DEFAULT_GRACE_PERIOD);
    }

    function test_WhenRouterIsValidContract_ShouldSetRouter() external {
        DexSwapModuleFactory newFactory = new DexSwapModuleFactory(address(router), sequencerFeed, DEFAULT_GRACE_PERIOD);
        assertEq(newFactory.router(), address(router));
    }

    function test_WhenRouterIsValidContract_ShouldSetSequencerUptimeFeed() external {
        DexSwapModuleFactory newFactory = new DexSwapModuleFactory(address(router), sequencerFeed, DEFAULT_GRACE_PERIOD);
        assertEq(newFactory.sequencerUptimeFeed(), sequencerFeed);
    }

    function test_WhenRouterIsValidContract_ShouldSetSequencerGracePeriod() external {
        DexSwapModuleFactory newFactory = new DexSwapModuleFactory(address(router), sequencerFeed, DEFAULT_GRACE_PERIOD);
        assertEq(newFactory.sequencerGracePeriod(), DEFAULT_GRACE_PERIOD);
    }

    /// @dev L1 has no sequencer uptime feed, so address(0) must stay a valid configuration.
    function test_WhenSequencerFeedIsZero_ShouldDeployForL1Profile() external {
        DexSwapModuleFactory newFactory = new DexSwapModuleFactory(address(router), address(0), 0);
        assertEq(newFactory.sequencerUptimeFeed(), address(0));
        assertEq(newFactory.sequencerGracePeriod(), 0);
    }
}
