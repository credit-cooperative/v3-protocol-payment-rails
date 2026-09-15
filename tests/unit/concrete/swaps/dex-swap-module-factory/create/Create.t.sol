// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { DexSwapModuleFactoryBase } from "../DexSwapModuleFactoryBase.t.sol";
import { DexSwapModuleFactory } from "../../../../../../src/modules/swaps/DexSwapModuleFactory.sol";
import { DexSwapModule } from "../../../../../../src/modules/swaps/DexSwapModule.sol";

contract Create_DexSwapModuleFactory_Test is DexSwapModuleFactoryBase {
    /// @dev Deployment is deliberately permissionless: every module is wired identically from factory
    /// immutables and holds no privileged role, and the registry has no per-PaymentRails index, so a
    /// stranger's deployment asserts nothing about anyone else's instance.
    function test_WhenCalledByAnyAddress_ShouldDeployContract() external {
        vm.prank(deployer);
        address module = factory.create();
        assertTrue(module.code.length > 0);
    }

    function test_WhenCalledByAnyAddress_ShouldDeployDexSwapModule() external {
        vm.prank(deployer);
        address module = factory.create();
        assertEq(DexSwapModule(module).moduleType(), "SWAP");
    }

    function test_WhenCalledByAnyAddress_ShouldWireChainConfig() external {
        vm.prank(deployer);
        address module = factory.create();

        assertEq(DexSwapModule(module).router(), factory.router());
        assertEq(DexSwapModule(module).sequencerUptimeFeed(), factory.sequencerUptimeFeed());
        assertEq(DexSwapModule(module).sequencerGracePeriod(), factory.sequencerGracePeriod());
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
        emit DexSwapModuleCreated(address(0), deployer);

        vm.prank(deployer);
        factory.create();
    }

    /// @dev The L2 profile is what the factory immutables exist to guarantee: a module deployed from
    /// an L2 factory must carry that chain's sequencer uptime feed, not a default.
    function test_WhenFactoryHasL2Profile_ShouldWireSequencerConfig() external {
        DexSwapModuleFactory l2Factory = new DexSwapModuleFactory(address(router), sequencerFeed, DEFAULT_GRACE_PERIOD);

        vm.prank(deployer);
        address module = l2Factory.create();

        assertEq(DexSwapModule(module).sequencerUptimeFeed(), sequencerFeed);
        assertEq(DexSwapModule(module).sequencerGracePeriod(), DEFAULT_GRACE_PERIOD);
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

    function test_WhenCalledMultipleTimes_ShouldWireEveryInstanceIdentically() external {
        address stranger = makeAddr("stranger");

        vm.prank(deployer);
        address module1 = factory.create();

        vm.prank(stranger);
        address module2 = factory.create();

        assertEq(DexSwapModule(module1).router(), DexSwapModule(module2).router());
        assertEq(DexSwapModule(module1).sequencerUptimeFeed(), DexSwapModule(module2).sequencerUptimeFeed());
        assertEq(DexSwapModule(module1).sequencerGracePeriod(), DexSwapModule(module2).sequencerGracePeriod());
    }
}
