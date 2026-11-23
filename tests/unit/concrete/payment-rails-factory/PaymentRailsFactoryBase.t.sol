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
    event FactoryOperatorSet(address indexed sender, address indexed operator, bool indexed approved);

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
    address internal stranger;
    address internal operator;

    /*//////////////////////////////////////////////////////////////////////////
                                    SET UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        owner = makeAddr("owner");
        deployer = makeAddr("deployer");
        stranger = makeAddr("stranger");
        operator = makeAddr("operator");

        // The test contract is the factory owner, so create() calls in the suites below need no
        // prank; access control is exercised explicitly from `stranger`.
        factory = new PaymentRailsFactory(address(this));
    }

    /// @dev Approves `operator` as the factory owner (this contract). Not done in setUp so each test
    /// starts from the deployment state, where no operator exists.
    function _approveOperator() internal {
        factory.setFactoryOperator(operator, true);
    }
}
