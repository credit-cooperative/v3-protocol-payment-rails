// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { CCTPBridgeModuleFactoryBase } from "../CCTPBridgeModuleFactoryBase.t.sol";
import { CCTPBridgeModule } from "../../../../../../src/modules/bridges/CCTPBridgeModule.sol";

contract Create_CCTPBridgeModuleFactory_Test is CCTPBridgeModuleFactoryBase {
    /// @dev Deployment is deliberately permissionless: every module is wired identically from factory
    /// immutables and holds no privileged role, and the registry has no per-PaymentRails index, so a
    /// stranger's deployment asserts nothing about anyone else's instance.
    function test_WhenCalledByAnyAddress_ShouldDeployContract() external {
        vm.prank(deployer);
        address module = factory.create();
        assertTrue(module.code.length > 0);
    }

    function test_WhenCalledByAnyAddress_ShouldDeployCCTPBridgeModule() external {
        vm.prank(deployer);
        address module = factory.create();
        assertEq(CCTPBridgeModule(module).moduleType(), "CCTP_BRIDGE");
    }

    function test_WhenCalledByAnyAddress_ShouldWireChainConfig() external {
        vm.prank(deployer);
        address module = factory.create();

        assertEq(CCTPBridgeModule(module).tokenMessenger(), factory.tokenMessenger());
        assertEq(CCTPBridgeModule(module).usdc(), factory.usdc());
    }

    function test_WhenCalledByAnyAddress_ShouldRegisterModule() external {
        vm.prank(deployer);
        address module = factory.create();
        assertTrue(factory.isDeployedModule(module));
    }

    function test_WhenCalledByAnyAddress_ShouldIncrementModuleCount() external {
        assertEq(factory.getModuleCount(), 0);
        vm.prank(deployer);
        factory.create();
        assertEq(factory.getModuleCount(), 1);
    }

    function test_WhenCalledByAnyAddress_ShouldEmitEvent() external {
        // Topic1 (the CREATE address) is unpredictable; assert topic2 (deployer).
        vm.expectEmit(false, true, false, true);
        emit CCTPBridgeModuleCreated(address(0), deployer);

        vm.prank(deployer);
        factory.create();
    }

    function test_WhenCalledMultipleTimes_ShouldDeployDistinctInstances() external {
        vm.startPrank(deployer);
        address module1 = factory.create();
        address module2 = factory.create();
        vm.stopPrank();
        assertTrue(module1 != module2);
    }

    function test_WhenCalledMultipleTimes_ShouldRegisterAllInstances() external {
        vm.startPrank(deployer);
        address module1 = factory.create();
        address module2 = factory.create();
        vm.stopPrank();

        assertEq(factory.getModuleCount(), 2);

        address[] memory modules = factory.getDeployedModules();
        assertEq(modules.length, 2);
        assertEq(modules[0], module1);
        assertEq(modules[1], module2);
    }

    /// @dev Burning the wrong token through the wrong messenger is the failure mode that matters
    /// here, so every instance the registry lists must carry the same pinned pair.
    function test_WhenCalledMultipleTimes_ShouldWireEveryInstanceIdentically() external {
        address stranger = makeAddr("stranger");

        vm.prank(deployer);
        address module1 = factory.create();

        vm.prank(stranger);
        address module2 = factory.create();

        assertEq(CCTPBridgeModule(module1).tokenMessenger(), CCTPBridgeModule(module2).tokenMessenger());
        assertEq(CCTPBridgeModule(module1).usdc(), CCTPBridgeModule(module2).usdc());
    }
}
