// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { CowSwapModuleFactory } from "../../../../../src/modules/swaps/CowSwapModuleFactory.sol";

import { MockCowSettlement } from "../../../../shared/mocks/MockCowSettlement.sol";

/// @dev Base test contract for CowSwapModuleFactory unit tests.
abstract contract CowSwapModuleFactoryBase is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event CowSwapModuleCreated(address indexed module, address indexed paymentRails, address indexed owner);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    bytes32 internal constant DOMAIN_SEPARATOR = keccak256("cow.protocol.domain.separator.v1");
    bytes32 internal constant DEFAULT_SALT = bytes32(uint256(1));
    uint256 internal constant DEFAULT_GRACE_PERIOD = 3600;

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    CowSwapModuleFactory internal factory;
    MockCowSettlement internal cowSettlement;

    address internal owner;
    address internal paymentRails;
    address internal vaultRelayer;
    address internal sequencerFeed;

    /*//////////////////////////////////////////////////////////////////////////
                                    SET UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        owner = makeAddr("owner");
        paymentRails = makeAddr("paymentRails");
        vaultRelayer = makeAddr("vaultRelayer");
        sequencerFeed = makeAddr("sequencerFeed");

        cowSettlement = new MockCowSettlement(DOMAIN_SEPARATOR, vaultRelayer);

        // L1 profile: no sequencer uptime feed.
        factory = new CowSwapModuleFactory(address(cowSettlement), address(0), 0);
    }
}
