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
import { Errors } from "../../../../src/libraries/Errors.sol";
import { MockWETH9 } from "../../../shared/mocks/MockWETH9.sol";
import {
    RejectingRecipient,
    GasBurningRecipient,
    ReentrantNativeRecipient
} from "../../../shared/mocks/NativeMocks.sol";

/// @dev Tree: tests/integration/concrete/native/nativeRoutesIntegration.tree
contract NativeRoutesIntegrationTest is Test {
    event ActionExecuted(
        address indexed token,
        string actionType,
        uint256 amountIn,
        uint256 amountOut,
        address outputToken,
        address indexed executor
    );
    event ActionFailed(
        address indexed token, string actionType, uint256 amount, string reason, address indexed executor
    );
    event NativeReceived(address indexed sender, uint256 amount);
    event NativeReturned(address indexed sourceToken, address indexed module, uint256 amount);

    address internal constant NATIVE = Constants.NATIVE_TOKEN;
    uint256 internal constant VALUE = 2 ether;

    PaymentRails internal rails;
    MockWETH9 internal weth;
    WrapModule internal wrap;
    UnwrapModule internal unwrap;
    NativeForwardModule internal nativeForward;
    ForwardModule internal forward;

    address internal owner;
    address internal keeper;
    address internal recipient;

    function setUp() public {
        owner = makeAddr("owner");
        keeper = makeAddr("keeper");
        recipient = makeAddr("recipient");

        weth = new MockWETH9();
        rails = new PaymentRails(owner);
        wrap = new WrapModule(address(weth));
        unwrap = new UnwrapModule(address(weth));
        nativeForward = new NativeForwardModule();
        forward = new ForwardModule();

        vm.deal(keeper, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _routeNativeToWrap() internal {
        vm.prank(owner);
        rails.configureToken(NATIVE, "WRAP", address(wrap), 0, "", true);
    }

    function _routeNativeToForward(address to) internal {
        bytes memory params = nativeForward.encodeParams(DataTypes.ForwardParams({ recipient: to, minAmount: 0 }));
        vm.prank(owner);
        rails.configureToken(NATIVE, "NATIVE_FORWARD", address(nativeForward), 0, params, true);
    }

    function _routeWethToForward(address to) internal {
        bytes memory params = forward.encodeParams(DataTypes.ForwardParams({ recipient: to, minAmount: 0 }));
        vm.prank(owner);
        rails.configureToken(address(weth), "FORWARD", address(forward), 0, params, true);
    }

    function _routeWethToUnwrap() internal {
        vm.prank(owner);
        rails.configureToken(address(weth), "UNWRAP", address(unwrap), 0, "", true);
    }

    function _sendNative(uint256 amount) internal {
        vm.prank(keeper);
        (bool ok,) = address(rails).call{ value: amount }("");
        assertTrue(ok, "native send failed");
    }

    function _assertModulesClean() internal view {
        assertEq(address(wrap).balance, 0, "wrap native");
        assertEq(address(unwrap).balance, 0, "unwrap native");
        assertEq(address(nativeForward).balance, 0, "nativeForward native");
        assertEq(weth.balanceOf(address(wrap)), 0, "wrap weth");
        assertEq(weth.balanceOf(address(unwrap)), 0, "unwrap weth");
        assertEq(weth.balanceOf(address(forward)), 0, "forward weth");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_GivenNativeRoutedToWrapAndWrappedRoutedToForward() external {
        _routeNativeToWrap();
        _routeWethToForward(recipient);
        _sendNative(VALUE);

        (uint256 estimated, address outputToken) = rails.previewExecution(NATIVE);
        assertEq(estimated, VALUE, "preview amount");
        assertEq(outputToken, address(weth), "preview output token");

        vm.expectEmit(true, false, false, true, address(rails));
        emit ActionExecuted(NATIVE, "WRAP", VALUE, VALUE, address(weth), keeper);
        vm.prank(keeper);
        assertTrue(rails.executeAction(NATIVE, VALUE));

        assertEq(address(rails).balance, 0, "native after wrap");
        assertEq(weth.balanceOf(address(rails)), VALUE, "wrapped after wrap");

        vm.prank(keeper);
        assertTrue(rails.executeAction(address(weth), VALUE));

        assertEq(weth.balanceOf(recipient), VALUE, "recipient wrapped");
        assertEq(weth.balanceOf(address(rails)), 0, "rails wrapped");
        _assertModulesClean();
    }

    function test_GivenNativeRoutedToNativeForward_WhenTheRecipientIsAnEOA() external {
        _routeNativeToForward(recipient);
        _sendNative(VALUE);

        vm.expectEmit(true, false, false, true, address(rails));
        emit ActionExecuted(NATIVE, "NATIVE_FORWARD", VALUE, VALUE, NATIVE, keeper);
        vm.prank(keeper);
        assertTrue(rails.executeAction(NATIVE, VALUE));

        assertEq(recipient.balance, VALUE, "recipient native");
        assertEq(address(rails).balance, 0, "rails native");
        _assertModulesClean();
    }

    function test_GivenNativeRoutedToNativeForward_WhenTheRecipientRefuses() external {
        RejectingRecipient rejecting = new RejectingRecipient();
        _routeNativeToForward(address(rejecting));
        _sendNative(VALUE);

        vm.expectEmit(true, false, false, true, address(rails));
        emit ActionFailed(NATIVE, "NATIVE_FORWARD", VALUE, "Module execution reverted", keeper);
        vm.prank(keeper);
        assertFalse(rails.executeAction(NATIVE, VALUE));

        assertEq(address(rails).balance, VALUE, "native must stay on the rails");
        assertEq(address(rejecting).balance, 0, "recipient must receive nothing");
        _assertModulesClean();
    }

    function test_GivenNativeRoutedToNativeForward_WhenTheRecipientBurnsAllGas() external {
        GasBurningRecipient burner = new GasBurningRecipient();
        _routeNativeToForward(address(burner));
        _sendNative(VALUE);

        vm.prank(keeper);
        assertFalse(rails.executeAction{ gas: 3_000_000 }(NATIVE, VALUE));

        assertEq(address(rails).balance, VALUE, "native must stay on the rails");
        _assertModulesClean();
    }

    function test_GivenNativeRoutedToNativeForward_WhenTheRecipientReEntersExecuteAction() external {
        ReentrantNativeRecipient reentrant = new ReentrantNativeRecipient(rails);
        _routeNativeToForward(address(reentrant));
        _sendNative(VALUE);

        vm.prank(keeper);
        assertTrue(rails.executeAction(NATIVE, 1 ether));

        assertTrue(reentrant.reentrancyBlocked(), "nested executeAction must hit the reentrancy guard");
        assertEq(address(reentrant).balance, 1 ether, "recipient native");
        assertEq(address(rails).balance, VALUE - 1 ether, "rails native");
    }

    function test_GivenWrappedRoutedToUnwrapAndNativeRoutedToNativeForward() external {
        _routeWethToUnwrap();
        _routeNativeToForward(recipient);
        weth.deposit{ value: VALUE }();
        weth.transfer(address(rails), VALUE);

        vm.expectEmit(true, true, false, true, address(rails));
        emit NativeReturned(address(weth), address(unwrap), VALUE);
        vm.prank(keeper);
        assertTrue(rails.executeAction(address(weth), VALUE));

        assertEq(address(rails).balance, VALUE, "native after unwrap");
        assertEq(weth.balanceOf(address(rails)), 0, "wrapped after unwrap");

        vm.prank(keeper);
        assertTrue(rails.executeAction(NATIVE, VALUE));

        assertEq(recipient.balance, VALUE, "recipient native");
        _assertModulesClean();
    }

    function test_RevertWhen_TheNativeKeyIsConfiguredWithAnERC20OnlyModule() external {
        bytes memory params = forward.encodeParams(DataTypes.ForwardParams({ recipient: recipient, minAmount: 0 }));
        vm.expectRevert(Errors.PaymentRails_ModuleDoesNotSupportNative.selector);
        vm.prank(owner);
        rails.configureToken(NATIVE, "FORWARD", address(forward), 0, params, true);
    }

    function test_WhenAnERC20KeyIsRoutedToANativeOnlyModule() external {
        // The opposite mistake: WETH pointed at modules that only take value. Configuration is accepted
        // (they are valid action modules) but execution must fail softly and move nothing.
        weth.deposit{ value: VALUE }();
        weth.transfer(address(rails), VALUE);
        bytes memory params =
            nativeForward.encodeParams(DataTypes.ForwardParams({ recipient: recipient, minAmount: 0 }));

        vm.startPrank(owner);
        rails.configureToken(address(weth), "WRAP", address(wrap), 0, "", true);
        vm.stopPrank();
        vm.expectEmit(true, false, false, true, address(rails));
        emit ActionFailed(address(weth), "WRAP", VALUE, "Native input only", keeper);
        vm.prank(keeper);
        assertFalse(rails.executeAction(address(weth), VALUE));
        assertEq(weth.balanceOf(address(rails)), VALUE, "wrap: no funds moved");
        assertEq(weth.allowance(address(rails), address(wrap)), 0, "wrap: approval revoked");

        vm.prank(owner);
        rails.configureToken(address(weth), "NATIVE_FORWARD", address(nativeForward), 0, params, true);
        vm.prank(keeper);
        assertFalse(rails.executeAction(address(weth), VALUE));
        assertEq(weth.balanceOf(address(rails)), VALUE, "native forward: no funds moved");
        assertEq(weth.allowance(address(rails), address(nativeForward)), 0, "native forward: approval revoked");
        assertEq(recipient.balance, 0, "native forward: recipient untouched");
    }

    function test_GivenValueArrivedWithoutCallingReceive() external {
        // vm.deal models value that arrives without running receive()
        vm.deal(address(rails), VALUE);
        address safe = makeAddr("safe");
        _routeNativeToForward(safe);

        vm.prank(makeAddr("anyone"));
        assertTrue(rails.executeAction(NATIVE, VALUE));

        assertEq(safe.balance, VALUE, "forced value recovered through the route");
    }

    function test_WhenTheOwnerSwitchesTheNativeRoute() external {
        _routeNativeToWrap();
        _sendNative(VALUE);

        _routeNativeToForward(recipient);
        vm.prank(keeper);
        assertTrue(rails.executeAction(NATIVE, VALUE));

        assertEq(recipient.balance, VALUE, "only the current route applies");
        assertEq(weth.balanceOf(address(rails)), 0, "nothing was wrapped");
    }
}
