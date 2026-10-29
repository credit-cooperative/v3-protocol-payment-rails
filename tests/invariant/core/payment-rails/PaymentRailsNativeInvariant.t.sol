// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";

import { PaymentRails } from "../../../../src/core/PaymentRails.sol";
import { PaymentRailsNativeHandler } from "./PaymentRailsNativeHandler.sol";

/// @dev Native value enters through receive() or is force-fed, and leaves only by an owner sweep. Every quantity is
///      compared against the handler's ghost totals.
contract PaymentRailsNativeInvariant is Test {
    PaymentRails internal rails;
    PaymentRailsNativeHandler internal handler;

    address internal owner;
    address internal exitRecipient;

    function setUp() public {
        owner = makeAddr("owner");
        exitRecipient = makeAddr("exitRecipient");

        rails = new PaymentRails(owner);
        handler = new PaymentRailsNativeHandler(rails, owner, exitRecipient);

        targetContract(address(handler));
        excludeContract(address(rails));
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-N1: NATIVE CONSERVATION
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_NativeConservation() public view {
        assertEq(
            handler.ghost_nativeSent() + handler.ghost_nativeForced(),
            handler.ghost_swept() + address(rails).balance,
            "INV-N1: native in == swept + native still held"
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-N2: THE OWNER SWEEP IS THE ONLY NATIVE EGRESS
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_SweepIsTheOnlyNativeEgress() public view {
        assertEq(exitRecipient.balance, handler.ghost_swept(), "INV-N2: exit recipient holds exactly what was swept");
        assertEq(handler.rejectingRecipientAddress().balance, 0, "INV-N2: a refusing recipient never receives value");
    }
}
