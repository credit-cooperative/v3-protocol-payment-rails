// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { CCTPBridgeModuleFactory } from "../../../../../src/modules/bridges/CCTPBridgeModuleFactory.sol";

import { MockERC20 } from "../../../../shared/mocks/MockERC20.sol";
import { MockTokenMessengerV2 } from "../../../../shared/mocks/MockTokenMessengerV2.sol";

/// @dev Base test contract for CCTPBridgeModuleFactory unit tests.
abstract contract CCTPBridgeModuleFactoryBase is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event CCTPBridgeModuleCreated(address indexed module, address indexed deployer);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    bytes32 internal constant DEFAULT_SALT = bytes32(uint256(1));

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    CCTPBridgeModuleFactory internal factory;
    MockTokenMessengerV2 internal tokenMessenger;
    MockERC20 internal usdc;

    address internal deployer;

    /*//////////////////////////////////////////////////////////////////////////
                                    SET UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        deployer = makeAddr("deployer");

        tokenMessenger = new MockTokenMessengerV2();
        usdc = new MockERC20("USD Coin", "USDC");

        factory = new CCTPBridgeModuleFactory(address(tokenMessenger), address(usdc));
    }
}
