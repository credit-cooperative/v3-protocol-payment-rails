// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { DexSwapModuleFactory } from "../../../../../src/modules/swaps/DexSwapModuleFactory.sol";

import { MockRouter } from "../../../../shared/mocks/MockRouter.sol";

/// @dev Base test contract for DexSwapModuleFactory unit tests.
abstract contract DexSwapModuleFactoryBase is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event DexSwapModuleCreated(address indexed module, address indexed deployer);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    bytes32 internal constant DEFAULT_SALT = bytes32(uint256(1));
    uint256 internal constant DEFAULT_GRACE_PERIOD = 3600;

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    DexSwapModuleFactory internal factory;
    MockRouter internal router;

    address internal deployer;
    address internal sequencerFeed;

    /*//////////////////////////////////////////////////////////////////////////
                                    SET UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        deployer = makeAddr("deployer");
        sequencerFeed = makeAddr("sequencerFeed");

        router = new MockRouter();

        // L1 profile: no sequencer uptime feed.
        factory = new DexSwapModuleFactory(address(router), address(0), 0);
    }
}
