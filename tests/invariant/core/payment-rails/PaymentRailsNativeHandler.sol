// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { VmSafe } from "forge-std/src/Vm.sol";

import { PaymentRails } from "../../../../src/core/PaymentRails.sol";
import { Errors } from "../../../../src/libraries/Errors.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { StipendSender, RejectingRecipient } from "../../../shared/mocks/NativeMocks.sol";

/// @dev Drives native value in (call, stipend, force-fed) and lets the owner sweep it out, including attempted
///      sweeps by strangers and to a refusing recipient.
contract PaymentRailsNativeHandler is Test {
    PaymentRails internal rails;
    StipendSender internal stipendSender;
    RejectingRecipient internal rejectingRecipient;

    address internal owner;
    address internal exitRecipient;
    address[] internal actors;

    uint256 public ghost_nativeSent; // entered through receive()
    uint256 public ghost_nativeForced; // appeared without receive()
    uint256 public ghost_swept;

    constructor(PaymentRails _rails, address _owner, address _exitRecipient) {
        rails = _rails;
        owner = _owner;
        exitRecipient = _exitRecipient;
        stipendSender = new StipendSender();
        rejectingRecipient = new RejectingRecipient();
        actors.push(makeAddr("coordinator"));
        actors.push(makeAddr("keeper"));
        actors.push(makeAddr("stranger"));
    }

    function rejectingRecipientAddress() external view returns (address) {
        return address(rejectingRecipient);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NATIVE INGRESS
    //////////////////////////////////////////////////////////////////////////*/

    function handler_sendWithCall(uint256 actorSeed, uint256 amount) external {
        amount = bound(amount, 1, 100 ether);
        address actor = actors[actorSeed % actors.length];
        vm.deal(actor, amount);

        vm.prank(actor);
        (bool ok,) = address(rails).call{ value: amount }("");
        assertTrue(ok, "handler: full-gas native send must succeed");

        ghost_nativeSent += amount;
    }

    function handler_sendWithStipend(uint256 amount) external {
        amount = bound(amount, 1, 100 ether);
        vm.deal(address(stipendSender), amount);

        // Coverage instrumentation inflates receive() past the stipend; the stipend path is proven on the
        // optimized artifact, so under coverage this action degrades to a full-gas call.
        if (vm.isContext(VmSafe.ForgeContext.Coverage)) {
            assertTrue(stipendSender.sendWithCall(payable(address(rails)), amount), "handler: native send failed");
        } else {
            stipendSender.sendWithTransfer(payable(address(rails)), amount);
        }

        ghost_nativeSent += amount;
    }

    function handler_forceFeed(uint256 amount) external {
        amount = bound(amount, 1, 100 ether);

        vm.deal(address(rails), address(rails).balance + amount);

        ghost_nativeForced += amount;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  NATIVE EXIT
    //////////////////////////////////////////////////////////////////////////*/

    function handler_sweepNative(uint256 actorSeed, bool toRejecting) external {
        uint256 nativeBefore = address(rails).balance;
        address actor = actors[actorSeed % actors.length];

        // Only the owner may sweep; anyone else is rejected before any value moves.
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actor));
        vm.prank(actor);
        rails.sweepNative(actor);
        assertEq(address(rails).balance, nativeBefore, "handler: a stranger's sweep attempt must move nothing");

        if (nativeBefore == 0) {
            vm.expectRevert(Errors.PaymentRails_ZeroNativeBalance.selector);
            vm.prank(owner);
            rails.sweepNative(exitRecipient);
            return;
        }

        if (toRejecting) {
            vm.expectRevert(
                abi.encodeWithSelector(Errors.PaymentRails_NativeTransferFailed.selector, address(rejectingRecipient))
            );
            vm.prank(owner);
            rails.sweepNative(address(rejectingRecipient));
            assertEq(address(rails).balance, nativeBefore, "handler: refused sweep must move no native");
            return;
        }

        vm.prank(owner);
        uint256 swept = rails.sweepNative(exitRecipient);
        assertEq(swept, nativeBefore, "handler: sweep must report the whole native balance");

        ghost_swept += swept;
    }
}
