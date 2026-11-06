// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { BraleModuleFactory } from "../../../../../src/modules/redemptions/BraleModuleFactory.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";

/// @dev Base test contract for BraleModuleFactory unit tests.
abstract contract BraleModuleFactoryBase is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event BraleModuleCreated(address indexed module, address indexed paymentRails, address indexed owner);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    bytes32 internal constant DEFAULT_SALT = bytes32(uint256(1));

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    BraleModuleFactory internal factory;

    address internal owner;
    /// @dev Neither the factory owner nor any PaymentRails owner.
    address internal stranger;
    address internal paymentRails;
    /// @dev A second PaymentRails, also owned by this contract, for per-rails registry tests.
    address internal otherPaymentRails;
    /// @dev A real PaymentRails owned by someone other than the factory owner. Creation is gated on
    ///      the factory owner, not the PaymentRails owner.
    address internal foreignPaymentRails;
    address internal foreignRailsOwner;

    /*//////////////////////////////////////////////////////////////////////////
                                    SET UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        owner = makeAddr("owner");
        stranger = makeAddr("stranger");

        paymentRails = address(new PaymentRails(address(this)));
        otherPaymentRails = address(new PaymentRails(address(this)));

        foreignRailsOwner = makeAddr("foreignRailsOwner");
        foreignPaymentRails = address(new PaymentRails(foreignRailsOwner));

        // This test contract owns the factory, so every unpranked create call is made by the factory owner.
        factory = new BraleModuleFactory(address(this));
    }
}
