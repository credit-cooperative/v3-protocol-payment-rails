// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BraleModuleBase } from "../BraleModuleBase.t.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract BraleModule_ReturnToPaymentRails_Test is BraleModuleBase {
    function test_RevertWhen_CallerIsNotOwner() external {
        token.mint(address(module), 1e18);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        module.returnToPaymentRails(address(token));
    }

    function test_RevertWhen_BalanceIsZero() external {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.BraleModule_NothingToReturn.selector, address(token)));
        module.returnToPaymentRails(address(token));
    }

    function test_WhenStrayBalance_ReturnsFullBalanceToPaymentRails() external {
        token.mint(address(module), 7e18);
        uint256 railsBefore = token.balanceOf(address(paymentRails));

        vm.expectEmit(true, false, false, true, address(module));
        emit TokensReturned(address(token), 7e18);
        vm.prank(owner);
        uint256 amount = module.returnToPaymentRails(address(token));

        assertEq(amount, 7e18);
        assertEq(token.balanceOf(address(module)), 0);
        assertEq(token.balanceOf(address(paymentRails)), railsBefore + 7e18);
        assertEq(token.balanceOf(owner), 0);
    }
}
