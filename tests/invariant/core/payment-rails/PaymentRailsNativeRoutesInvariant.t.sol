// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";

import { PaymentRails } from "../../../../src/core/PaymentRails.sol";
import { ForwardModule } from "../../../../src/modules/forwards/ForwardModule.sol";
import { WrapModule } from "../../../../src/modules/native/WrapModule.sol";
import { UnwrapModule } from "../../../../src/modules/native/UnwrapModule.sol";
import { NativeForwardModule } from "../../../../src/modules/native/NativeForwardModule.sol";
import { DataTypes } from "../../../../src/types/DataTypes.sol";
import { Constants } from "../../../../src/libraries/Constants.sol";
import { MockWETH9 } from "../../../shared/mocks/MockWETH9.sol";
import { PaymentRailsNativeRoutesHandler } from "./PaymentRailsNativeRoutesHandler.sol";

/// @dev Native value and wrapped value can only move along the owner-configured route for their key; the
///      wrapper backs every outstanding wrapped unit; modules hold nothing between calls.
contract PaymentRailsNativeRoutesInvariant is Test {
    PaymentRails internal rails;
    MockWETH9 internal weth;
    WrapModule internal wrap;
    UnwrapModule internal unwrap;
    NativeForwardModule internal nativeForward;
    ForwardModule internal forward;
    PaymentRailsNativeRoutesHandler internal handler;

    address internal owner;

    function setUp() public {
        owner = makeAddr("owner");

        weth = new MockWETH9();
        rails = new PaymentRails(owner);
        wrap = new WrapModule(address(weth));
        unwrap = new UnwrapModule(address(weth));
        nativeForward = new NativeForwardModule();
        forward = new ForwardModule();

        handler = new PaymentRailsNativeRoutesHandler(rails, weth, wrap, unwrap, nativeForward, forward, owner);

        // Initial routes: native -> WRAP, wrapped -> FORWARD to the wrapped recipient.
        bytes memory params =
            forward.encodeParams(DataTypes.ForwardParams({ recipient: handler.wrappedRecipient(), minAmount: 0 }));
        vm.startPrank(owner);
        rails.configureToken(Constants.NATIVE_TOKEN, "WRAP", address(wrap), 0, "", true);
        rails.configureToken(address(weth), "FORWARD", address(forward), 0, params, true);
        vm.stopPrank();

        targetContract(address(handler));
        excludeContract(address(rails));
        excludeContract(address(weth));
        excludeContract(address(wrap));
        excludeContract(address(unwrap));
        excludeContract(address(nativeForward));
        excludeContract(address(forward));
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-R1: NATIVE CONSERVATION
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_NativeConservation() public view {
        assertEq(
            address(rails).balance + handler.ghost_wrapped() + handler.ghost_nativeOut(),
            handler.ghost_nativeSent() + handler.ghost_nativeForced() + handler.ghost_unwrapped(),
            "INV-R1: native held + wrapped + paid out == native in + unwrapped"
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-R2: WRAPPED CONSERVATION
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_WrappedConservation() public view {
        assertEq(
            weth.balanceOf(address(rails)) + handler.ghost_unwrapped() + handler.ghost_wrappedOut(),
            handler.ghost_wrapped(),
            "INV-R2: wrapped held + unwrapped + forwarded == wrapped"
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-R3: THE WRAPPER BACKS EVERY OUTSTANDING UNIT
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_WrapperBacking() public view {
        assertEq(
            address(weth).balance + handler.ghost_unwrapped(),
            handler.ghost_wrapped(),
            "INV-R3: wrapper native == wrapped - unwrapped"
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-R4: RECIPIENTS HOLD EXACTLY WHAT WAS ROUTED TO THEM
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_RecipientsMatchGhosts() public view {
        assertEq(handler.nativeRecipient().balance, handler.ghost_nativeOut(), "INV-R4: native recipient");
        assertEq(weth.balanceOf(handler.wrappedRecipient()), handler.ghost_wrappedOut(), "INV-R4: wrapped recipient");
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-R5: MODULES HOLD NOTHING
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_ModulesHoldNothing() public view {
        assertEq(address(wrap).balance + address(unwrap).balance + address(nativeForward).balance, 0, "INV-R5: native");
        assertEq(
            weth.balanceOf(address(wrap)) + weth.balanceOf(address(unwrap)) + weth.balanceOf(address(forward)),
            0,
            "INV-R5: wrapped"
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INV-R6: IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_ImmutablesNeverChange() public view {
        assertEq(wrap.wrappedNative(), address(weth), "INV-R6: wrap wrapper");
        assertEq(unwrap.wrappedNative(), address(weth), "INV-R6: unwrap wrapper");
        assertEq(rails.NATIVE_TOKEN(), Constants.NATIVE_TOKEN, "INV-R6: sentinel");
    }
}
