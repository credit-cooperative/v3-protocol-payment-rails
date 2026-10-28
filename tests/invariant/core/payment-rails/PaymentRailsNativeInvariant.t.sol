// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";

import { PaymentRails } from "../../../../src/core/PaymentRails.sol";
import { ForwardModule } from "../../../../src/modules/forwards/ForwardModule.sol";
import { DataTypes } from "../../../../src/types/DataTypes.sol";
import { MockWETH9 } from "../../../shared/mocks/MockWETH9.sol";
import { PaymentRailsNativeHandler } from "./PaymentRailsNativeHandler.sol";

/// @dev Native value leaves the rails only by an owner wrap into its own wrapped balance, which flows out through the
///      configured route, or by an owner sweep that unwraps everything first. Every quantity is compared
///      against the handler's ghost totals.
contract PaymentRailsNativeInvariant is Test {
    PaymentRails internal rails;
    MockWETH9 internal weth;
    ForwardModule internal forwardModule;
    PaymentRailsNativeHandler internal handler;

    address internal owner;
    address internal recipient;
    address internal exitRecipient;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");
        exitRecipient = makeAddr("exitRecipient");

        weth = new MockWETH9();
        forwardModule = new ForwardModule();
        rails = new PaymentRails(owner, address(weth));

        bytes memory params =
            forwardModule.encodeParams(DataTypes.ForwardParams({ recipient: recipient, minAmount: 0 }));
        vm.prank(owner);
        rails.configureToken(address(weth), "FORWARD", address(forwardModule), 0, params, true);

        handler = new PaymentRailsNativeHandler(rails, weth, owner, exitRecipient);

        targetContract(address(handler));
        excludeContract(address(rails));
        excludeContract(address(weth));
        excludeContract(address(forwardModule));
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-N1: NATIVE CONSERVATION
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_NativeConservation() public view {
        assertEq(
            handler.ghost_nativeSent() + handler.ghost_nativeForced() + handler.ghost_unwrapped(),
            handler.ghost_wrapped() + handler.ghost_swept() + address(rails).balance,
            "INV-N1: native in + unwrapped == wrapped + swept + native still held"
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-N2: WRAPPED CONSERVATION
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_WrappedConservation() public view {
        assertEq(
            weth.balanceOf(address(rails)) + handler.ghost_forwarded() + handler.ghost_unwrapped(),
            handler.ghost_wrapped(),
            "INV-N2: rails wrapped + forwarded + unwrapped == wrapped"
        );
        assertEq(weth.balanceOf(recipient), handler.ghost_forwarded(), "INV-N2: recipient holds forwarded");
        assertEq(weth.balanceOf(address(forwardModule)), 0, "INV-N2: stateless module holds nothing");
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-N3: WRAP SWEEPS EVERYTHING
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_WrapLeavesNoNative() public view {
        assertEq(handler.ghost_maxLeftoverAfterWrap(), 0, "INV-N3: native balance must be zero after every wrap");
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-N4: THE WRAPPER HOLDS THE VALUE
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_WrapperBacking() public view {
        assertEq(
            address(weth).balance + handler.ghost_unwrapped(),
            handler.ghost_wrapped(),
            "INV-N4: wrapper native == wrapped - unwrapped"
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-N5: IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_WrappedNativeNeverChanges() public view {
        assertEq(rails.wrappedNative(), address(weth), "INV-N5: wrappedNative must never change");
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-N6: THE OWNER SWEEP IS THE ONLY NATIVE EGRESS
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_ExitIsTheOnlyNativeEgress() public view {
        assertEq(exitRecipient.balance, handler.ghost_swept(), "INV-N6: exit recipient holds exactly what was swept");
        assertEq(handler.rejectingRecipientAddress().balance, 0, "INV-N6: a refusing recipient never receives value");
    }
}
