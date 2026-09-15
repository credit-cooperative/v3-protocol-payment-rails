// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ForwardModuleFactoryBase } from "../ForwardModuleFactoryBase.t.sol";
import { ForwardModule } from "../../../../../../src/modules/forwards/ForwardModule.sol";

contract Create_ForwardModuleFactory_Test is ForwardModuleFactoryBase {
    /// @dev Deployment is deliberately permissionless: the registry has no per-PaymentRails index,
    /// so a stranger's deployment asserts nothing about anyone else's instance.
    function test_WhenCalledByAnyAddress_ShouldDeployContract() external {
        vm.prank(deployer);
        address module = factory.create();
        assertTrue(module.code.length > 0);
    }

    function test_WhenCalledByAnyAddress_ShouldDeployForwardModule() external {
        vm.prank(deployer);
        address module = factory.create();
        assertEq(ForwardModule(module).moduleType(), "FORWARD");
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
        emit ForwardModuleCreated(address(0), deployer);

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

        assertTrue(factory.isDeployedModule(module1));
        assertTrue(factory.isDeployedModule(module2));
        assertEq(factory.getModuleCount(), 2);

        address[] memory modules = factory.getDeployedModules();
        assertEq(modules.length, 2);
        assertEq(modules[0], module1);
        assertEq(modules[1], module2);
    }
}
