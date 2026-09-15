// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { CCTPBridgeModuleFactoryBase } from "../CCTPBridgeModuleFactoryBase.t.sol";
import { CCTPBridgeModuleFactory } from "../../../../../../src/modules/bridges/CCTPBridgeModuleFactory.sol";
import { Errors } from "../../../../../../src/libraries/Errors.sol";

contract Constructor_CCTPBridgeModuleFactory_Test is CCTPBridgeModuleFactoryBase {
    function test_RevertWhen_TokenMessengerIsZeroAddress() external {
        vm.expectRevert(Errors.CCTPBridgeModuleFactory_ZeroTokenMessenger.selector);
        new CCTPBridgeModuleFactory(address(0), address(usdc));
    }

    function test_RevertWhen_TokenMessengerHasNoCode() external {
        address eoa = makeAddr("eoaMessenger");
        vm.expectRevert(abi.encodeWithSelector(Errors.CCTPBridgeModuleFactory_TokenMessengerNotContract.selector, eoa));
        new CCTPBridgeModuleFactory(eoa, address(usdc));
    }

    function test_RevertWhen_UsdcIsZeroAddress() external {
        vm.expectRevert(Errors.CCTPBridgeModuleFactory_ZeroUSDC.selector);
        new CCTPBridgeModuleFactory(address(tokenMessenger), address(0));
    }

    function test_RevertWhen_UsdcHasNoCode() external {
        address eoa = makeAddr("eoaUsdc");
        vm.expectRevert(abi.encodeWithSelector(Errors.CCTPBridgeModuleFactory_USDCNotContract.selector, eoa));
        new CCTPBridgeModuleFactory(address(tokenMessenger), eoa);
    }

    function test_WhenAddressesAreValidContracts_ShouldSetTokenMessenger() external {
        CCTPBridgeModuleFactory newFactory = new CCTPBridgeModuleFactory(address(tokenMessenger), address(usdc));
        assertEq(newFactory.tokenMessenger(), address(tokenMessenger));
    }

    function test_WhenAddressesAreValidContracts_ShouldSetUsdc() external {
        CCTPBridgeModuleFactory newFactory = new CCTPBridgeModuleFactory(address(tokenMessenger), address(usdc));
        assertEq(newFactory.usdc(), address(usdc));
    }
}
