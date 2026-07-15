// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { AtumModuleFactory } from "../../../../../../src/modules/contrib/bridges/AtumModuleFactory.sol";

import { MockPermit2 } from "../../../../../shared/mocks/atum/MockPermit2.sol";

/// @dev Base test contract for AtumModuleFactory unit tests.
abstract contract AtumModuleFactoryBase is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event AtumModuleCreated(address indexed module, address indexed paymentRails, address indexed owner);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    bytes32 internal constant PERMIT2_DOMAIN_SEPARATOR = keccak256("mock permit2 domain");
    bytes32 internal constant DEFAULT_SALT = bytes32(uint256(1));

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    AtumModuleFactory internal factory;
    MockPermit2 internal permit2;

    address internal owner;
    address internal paymentRails;
    address internal keeper;

    /*//////////////////////////////////////////////////////////////////////////
                                    SET UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        owner = makeAddr("owner");
        paymentRails = makeAddr("paymentRails");
        keeper = makeAddr("keeper");

        permit2 = new MockPermit2(PERMIT2_DOMAIN_SEPARATOR);
        factory = new AtumModuleFactory(address(permit2));
    }
}
