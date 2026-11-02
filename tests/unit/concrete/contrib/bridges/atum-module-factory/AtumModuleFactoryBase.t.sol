// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { AtumModuleFactory } from "../../../../../../src/modules/contrib/bridges/AtumModuleFactory.sol";

import { MockPermit2 } from "../../../../../shared/mocks/atum/MockPermit2.sol";
import { PaymentRails } from "../../../../../../src/core/PaymentRails.sol";

/// @dev Base test contract for AtumModuleFactory unit tests.
abstract contract AtumModuleFactoryBase is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event AtumModuleCreated(
        address indexed module, address indexed paymentRails, address indexed owner, address keeper
    );

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
    /// @dev Neither the factory owner nor any PaymentRails owner.
    address internal stranger;
    address internal paymentRails;
    address internal keeper;
    /// @dev A second PaymentRails, also owned by this contract, for per-rails registry tests.
    address internal otherPaymentRails;
    /// @dev A real PaymentRails owned by someone other than the factory owner. Creation is gated on
    ///      the factory owner, not the PaymentRails owner, so this must still be creatable.
    address internal foreignPaymentRails;
    address internal foreignRailsOwner;

    /*//////////////////////////////////////////////////////////////////////////
                                    SET UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        owner = makeAddr("owner");
        keeper = makeAddr("keeper");
        stranger = makeAddr("stranger");

        // Real PaymentRails instances: creation requires `paymentRails` to have code, so it cannot
        // be a bare `makeAddr`. No PaymentRailsFactory is involved; the AtumModuleFactory is not
        // bound to one.
        paymentRails = address(new PaymentRails(address(this)));

        otherPaymentRails = address(new PaymentRails(address(this)));

        foreignRailsOwner = makeAddr("foreignRailsOwner");
        foreignPaymentRails = address(new PaymentRails(foreignRailsOwner));

        permit2 = new MockPermit2(PERMIT2_DOMAIN_SEPARATOR);
        // This test contract owns the factory (Certora L-01), so every unpranked
        // `factory.create(...)` call is made by the factory owner.
        factory = new AtumModuleFactory(address(this), address(permit2));
    }
}
