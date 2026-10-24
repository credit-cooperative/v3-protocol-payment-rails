// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { PaymentRails } from "../../../../src/core/PaymentRails.sol";
import { Constants } from "../../../../src/libraries/Constants.sol";
import { MockERC20 } from "../../../shared/mocks/MockERC20.sol";
import { MockWETH9 } from "../../../shared/mocks/MockWETH9.sol";
import { MockActionModule } from "../../../shared/mocks/MockActionModule.sol";
import { MockNativeActionModule } from "../../../shared/mocks/MockNativeActionModule.sol";

/// @dev Base test contract for PaymentRails unit tests.
///      Provides shared state, constants, mocks, modifiers, and helpers following Sablier BTT style.
abstract contract PaymentRailsBase is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event TokenConfigured(address indexed token, string actionType, address actionModule);

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

    event NativeActionReverted(address indexed module, bytes revertData);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    uint256 internal constant INITIAL_BALANCE = 1000e18;
    uint256 internal constant MIN_BALANCE = 100e18;
    uint256 internal constant NATIVE_MIN = 0.1 ether;
    string internal constant ACTION_TYPE = "MOCK";
    string internal constant NATIVE_ACTION_TYPE = "NATIVE_MOCK";
    address internal constant NATIVE = Constants.NATIVE_TOKEN;

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    PaymentRails internal paymentRails;
    MockActionModule internal actionModule;
    MockNativeActionModule internal nativeModule;
    MockERC20 internal token;
    MockWETH9 internal weth;

    address internal owner;
    address internal nonOwner;
    address internal executor;
    address internal recipient;

    /*//////////////////////////////////////////////////////////////////////////
                                    SET UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");
        executor = makeAddr("executor");
        recipient = makeAddr("recipient");

        vm.startPrank(owner);
        paymentRails = new PaymentRails(owner);
        vm.stopPrank();

        actionModule = new MockActionModule();
        nativeModule = new MockNativeActionModule();
        token = new MockERC20("Test Token", "TEST");
        weth = new MockWETH9();

        token.mint(address(paymentRails), INITIAL_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    modifier whenCallerIsOwner() {
        vm.startPrank(owner);
        _;
        vm.stopPrank();
    }

    modifier whenCallerIsNotOwner() {
        vm.startPrank(nonOwner);
        _;
        vm.stopPrank();
    }

    modifier givenTokenConfigured() {
        vm.prank(owner);
        paymentRails.configureToken(
            address(token), ACTION_TYPE, address(actionModule), MIN_BALANCE, _defaultModuleParams(), true
        );
        _;
    }

    modifier givenTokenConfiguredDisabled() {
        vm.prank(owner);
        paymentRails.configureToken(
            address(token), ACTION_TYPE, address(actionModule), MIN_BALANCE, _defaultModuleParams(), false
        );
        _;
    }

    modifier givenNativeConfigured() {
        vm.prank(owner);
        paymentRails.configureToken(NATIVE, NATIVE_ACTION_TYPE, address(nativeModule), NATIVE_MIN, "", true);
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _defaultModuleParams() internal pure returns (bytes memory) {
        return abi.encode(uint256(0));
    }

    /// @dev Sends `amount` of native value from `from` to the rails with a full-gas call.
    function _sendNative(address from, uint256 amount) internal {
        vm.deal(from, from.balance + amount);
        vm.prank(from);
        (bool ok,) = address(paymentRails).call{ value: amount }("");
        assertTrue(ok, "native send failed");
    }
}
