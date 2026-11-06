// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BraleModuleBase } from "../BraleModuleBase.t.sol";
import { BraleModule } from "../../../../../../src/modules/redemptions/BraleModule.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract BraleModule_Constructor_Test is BraleModuleBase {
    function test_RevertWhen_PaymentRailsIsZeroAddress() external {
        vm.expectRevert(Errors.BraleModule_ZeroPaymentRails.selector);
        new BraleModule(address(0), owner);
    }

    function test_RevertWhen_OwnerIsZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new BraleModule(address(paymentRails), address(0));
    }

    function test_WhenParamsAreValid_SetsPaymentRails() external {
        BraleModule m = new BraleModule(address(paymentRails), owner);
        assertEq(m.paymentRails(), address(paymentRails));
    }

    function test_WhenParamsAreValid_SetsOwner() external {
        BraleModule m = new BraleModule(address(paymentRails), owner);
        assertEq(m.owner(), owner);
    }

    function test_WhenParamsAreValid_NonceStartsAtZero() external {
        BraleModule m = new BraleModule(address(paymentRails), owner);
        assertEq(m.redemptionNonce(), 0);
    }
}
