// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { NonNativeModuleMock } from "../../../../shared/mocks/MockNativeActionModule.sol";
import { ForwardModule } from "../../../../../src/modules/forwards/ForwardModule.sol";
import { DexSwapModule } from "../../../../../src/modules/swaps/DexSwapModule.sol";
import { CowSwapModule } from "../../../../../src/modules/swaps/CowSwapModule.sol";
import { CCTPBridgeModule } from "../../../../../src/modules/bridges/CCTPBridgeModule.sol";
import { UnwrapModule } from "../../../../../src/modules/native/UnwrapModule.sol";
import { MockRouter } from "../../../../shared/mocks/MockRouter.sol";
import { MockTokenMessengerV2 } from "../../../../shared/mocks/MockTokenMessengerV2.sol";
import { MockCowSettlement } from "../../../../shared/mocks/MockCowSettlement.sol";

contract PaymentRailsConfigureTokenNativeTest is PaymentRailsBase {
    function test_RevertWhen_TheModuleDoesNotExposeSupportsNativeInput() external whenCallerIsOwner {
        NonNativeModuleMock plain = new NonNativeModuleMock();

        vm.expectRevert(Errors.PaymentRails_ModuleDoesNotSupportNative.selector);
        paymentRails.configureToken(NATIVE, "PLAIN", address(plain), 0, "", true);

        // the existing ERC-20 mock has a moduleType() but no native entry point either
        vm.expectRevert(Errors.PaymentRails_ModuleDoesNotSupportNative.selector);
        paymentRails.configureToken(NATIVE, ACTION_TYPE, address(actionModule), 0, "", true);
    }

    /// @dev Every shipped ERC-20 module must be rejected on the native key: value can only be pushed to a module
    ///      that declares it takes value, so an owner slip like NATIVE -> SWAP cannot strand funds.
    function test_RevertWhen_TheModuleIsAnyExistingERC20Module() external {
        address[5] memory modules = [
            address(new ForwardModule()),
            address(new DexSwapModule(address(new MockRouter()), address(0), 0)),
            address(
                new CowSwapModule(
                    address(new MockCowSettlement(bytes32(uint256(1)), makeAddr("vaultRelayer"))),
                    owner,
                    address(paymentRails),
                    address(0),
                    0
                )
            ),
            address(new CCTPBridgeModule(address(new MockTokenMessengerV2()), address(token))),
            address(new UnwrapModule(address(weth)))
        ];
        string[5] memory types = ["FORWARD", "SWAP", "SWAP", "BRIDGE", "UNWRAP"];

        for (uint256 i; i < modules.length; ++i) {
            vm.expectRevert(Errors.PaymentRails_ModuleDoesNotSupportNative.selector);
            vm.prank(owner);
            paymentRails.configureToken(NATIVE, types[i], modules[i], 0, "", true);
            assertEq(bytes(paymentRails.getTokenConfig(NATIVE).actionType).length, 0, "nothing stored");
        }
    }

    function test_RevertWhen_TheModuleReportsNoNativeSupport() external whenCallerIsOwner {
        nativeModule.setSupportsNative(false);

        vm.expectRevert(Errors.PaymentRails_ModuleDoesNotSupportNative.selector);
        paymentRails.configureToken(NATIVE, NATIVE_ACTION_TYPE, address(nativeModule), 0, "", true);
    }

    function test_WhenTheModuleSupportsNativeInput() external whenCallerIsOwner {
        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit TokenConfigured(NATIVE, NATIVE_ACTION_TYPE, address(nativeModule));

        paymentRails.configureToken(NATIVE, NATIVE_ACTION_TYPE, address(nativeModule), NATIVE_MIN, "", true);

        DataTypes.TokenConfig memory config = paymentRails.getTokenConfig(NATIVE);
        assertEq(config.actionType, NATIVE_ACTION_TYPE, "actionType");
        assertEq(config.actionModule, address(nativeModule), "actionModule");
        assertEq(config.minBalance, NATIVE_MIN, "minBalance");
        assertTrue(config.enabled, "enabled");
    }

    function test_WhenClearingTheNativeConfiguration() external givenNativeConfigured whenCallerIsOwner {
        paymentRails.configureToken(NATIVE, "", address(0), 0, "", false);

        DataTypes.TokenConfig memory config = paymentRails.getTokenConfig(NATIVE);
        assertEq(bytes(config.actionType).length, 0, "actionType cleared");
        assertEq(config.actionModule, address(0), "actionModule cleared");
    }
}
