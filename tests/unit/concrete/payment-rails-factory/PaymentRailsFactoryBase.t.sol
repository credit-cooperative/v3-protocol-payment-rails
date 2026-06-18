// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { PaymentRailsFactory } from "../../../../src/core/PaymentRailsFactory.sol";

/// @dev Base test contract for PaymentRailsFactory unit tests.
abstract contract PaymentRailsFactoryBase is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event PaymentRailsCreated(address indexed paymentRails, address indexed owner);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    bytes32 internal constant DEFAULT_SALT = bytes32(uint256(1));

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    PaymentRailsFactory internal factory;

    address internal owner;
    address internal deployer;

    /*//////////////////////////////////////////////////////////////////////////
                                    SET UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        owner = makeAddr("owner");
        deployer = makeAddr("deployer");

        factory = new PaymentRailsFactory();
    }
}
