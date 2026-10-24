// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { VmSafe } from "forge-std/src/Vm.sol";

import { PaymentRails } from "../../../../src/core/PaymentRails.sol";
import { ForwardModule } from "../../../../src/modules/forwards/ForwardModule.sol";
import { WrapModule } from "../../../../src/modules/native/WrapModule.sol";
import { UnwrapModule } from "../../../../src/modules/native/UnwrapModule.sol";
import { NativeForwardModule } from "../../../../src/modules/native/NativeForwardModule.sol";
import { DataTypes } from "../../../../src/types/DataTypes.sol";
import { Constants } from "../../../../src/libraries/Constants.sol";
import { MockWETH9 } from "../../../shared/mocks/MockWETH9.sol";
import { StipendSender } from "../../../shared/mocks/NativeMocks.sol";

/// @dev Drives native value in (call, stipend, force-fed) and routes both the native key and the wrapped
///      token through every available route, with the owner switching routes at random. Ghost totals are
///      kept independently of the contracts.
contract PaymentRailsNativeRoutesHandler is Test {
    PaymentRails internal rails;
    MockWETH9 internal weth;
    WrapModule internal wrap;
    UnwrapModule internal unwrap;
    NativeForwardModule internal nativeForward;
    ForwardModule internal forward;
    StipendSender internal stipendSender;

    address internal owner;
    address public nativeRecipient;
    address public wrappedRecipient;
    address[] internal actors;

    uint256 public ghost_nativeSent;
    uint256 public ghost_nativeForced;
    uint256 public ghost_wrapped;
    uint256 public ghost_unwrapped;
    uint256 public ghost_nativeOut;
    uint256 public ghost_wrappedOut;
    bool public nativeRouteIsWrap = true;
    bool public wrappedRouteIsUnwrap;

    constructor(
        PaymentRails _rails,
        MockWETH9 _weth,
        WrapModule _wrap,
        UnwrapModule _unwrap,
        NativeForwardModule _nativeForward,
        ForwardModule _forward,
        address _owner
    ) {
        rails = _rails;
        weth = _weth;
        wrap = _wrap;
        unwrap = _unwrap;
        nativeForward = _nativeForward;
        forward = _forward;
        owner = _owner;
        stipendSender = new StipendSender();
        nativeRecipient = makeAddr("nativeRecipient");
        wrappedRecipient = makeAddr("wrappedRecipient");
        actors.push(makeAddr("coordinator"));
        actors.push(makeAddr("keeper"));
        actors.push(makeAddr("stranger"));
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
                                ROUTE SWITCHES
    //////////////////////////////////////////////////////////////////////////*/

    function handler_setNativeRoute(bool useWrap) external {
        vm.startPrank(owner);
        if (useWrap) {
            rails.configureToken(Constants.NATIVE_TOKEN, "WRAP", address(wrap), 0, "", true);
        } else {
            bytes memory params =
                nativeForward.encodeParams(DataTypes.ForwardParams({ recipient: nativeRecipient, minAmount: 0 }));
            rails.configureToken(Constants.NATIVE_TOKEN, "NATIVE_FORWARD", address(nativeForward), 0, params, true);
        }
        vm.stopPrank();

        nativeRouteIsWrap = useWrap;
    }

    function handler_setWrappedRoute(bool useUnwrap) external {
        vm.startPrank(owner);
        if (useUnwrap) {
            rails.configureToken(address(weth), "UNWRAP", address(unwrap), 0, "", true);
        } else {
            bytes memory params =
                forward.encodeParams(DataTypes.ForwardParams({ recipient: wrappedRecipient, minAmount: 0 }));
            rails.configureToken(address(weth), "FORWARD", address(forward), 0, params, true);
        }
        vm.stopPrank();

        wrappedRouteIsUnwrap = useUnwrap;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   EXECUTION
    //////////////////////////////////////////////////////////////////////////*/

    function handler_executeNative(uint256 actorSeed, uint256 amount) external {
        uint256 balance = address(rails).balance;
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        address actor = actors[actorSeed % actors.length];

        vm.prank(actor);
        bool ok = rails.executeAction(Constants.NATIVE_TOKEN, amount);
        assertTrue(ok, "handler: native route must succeed");

        if (nativeRouteIsWrap) ghost_wrapped += amount;
        else ghost_nativeOut += amount;
    }

    function handler_executeWrapped(uint256 actorSeed, uint256 amount) external {
        uint256 balance = weth.balanceOf(address(rails));
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        address actor = actors[actorSeed % actors.length];

        vm.prank(actor);
        bool ok = rails.executeAction(address(weth), amount);
        assertTrue(ok, "handler: wrapped route must succeed");

        if (wrappedRouteIsUnwrap) ghost_unwrapped += amount;
        else ghost_wrappedOut += amount;
    }
}
