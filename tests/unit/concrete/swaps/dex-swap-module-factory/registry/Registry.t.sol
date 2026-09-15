// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { DexSwapModuleFactoryBase } from "../DexSwapModuleFactoryBase.t.sol";
import { DexSwapModule } from "../../../../../../src/modules/swaps/DexSwapModule.sol";

import { MockRouter } from "../../../../../shared/mocks/MockRouter.sol";

contract Registry_DexSwapModuleFactory_Test is DexSwapModuleFactoryBase {
    /*//////////////////////////////////////////////////////////////////////////
                            GIVEN NO MODULES DEPLOYED
    //////////////////////////////////////////////////////////////////////////*/

    function test_GivenNoModules_IsDeployedModule_ShouldReturnFalse() external view {
        assertFalse(factory.isDeployedModule(address(0x1)));
    }

    function test_GivenNoModules_GetDeployedModules_ShouldReturnEmptyArray() external view {
        assertEq(factory.getDeployedModules().length, 0);
    }

    function test_GivenNoModules_GetModuleCount_ShouldReturnZero() external view {
        assertEq(factory.getModuleCount(), 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            GIVEN MODULES DEPLOYED
    //////////////////////////////////////////////////////////////////////////*/

    function test_GivenModules_IsDeployedModule_ShouldReturnTrueForDeployed() external {
        vm.prank(deployer);
        address module = factory.create();
        assertTrue(factory.isDeployedModule(module));
    }

    function test_GivenModules_IsDeployedModule_ShouldReturnFalseForNonDeployed() external {
        vm.prank(deployer);
        factory.create();
        assertFalse(factory.isDeployedModule(address(0xdead)));
    }

    /// @dev The whole point of pinning the router as a factory immutable: a module wired to a rogue
    /// router is the dangerous case, and it must not read as registered.
    function test_GivenModules_IsDeployedModule_ShouldReturnFalseForOutsideModuleWithRogueRouter() external {
        vm.prank(deployer);
        factory.create();

        MockRouter rogueRouter = new MockRouter();
        address rogue = address(new DexSwapModule(address(rogueRouter), address(0), 0));

        assertFalse(factory.isDeployedModule(rogue));
        assertTrue(DexSwapModule(rogue).router() != factory.router());
    }

    function test_GivenModules_GetDeployedModules_ShouldReturnCorrectArray() external {
        vm.startPrank(deployer);
        address module1 = factory.create();
        address module2 = factory.create();
        vm.stopPrank();

        address[] memory modules = factory.getDeployedModules();
        assertEq(modules.length, 2);
        assertEq(modules[0], module1);
        assertEq(modules[1], module2);
    }

    function test_GivenModules_GetModuleCount_ShouldReturnCorrectCount() external {
        vm.startPrank(deployer);
        factory.create();
        factory.create();
        factory.create();
        vm.stopPrank();
        assertEq(factory.getModuleCount(), 3);
    }

    /*//////////////////////////////////////////////////////////////////////////
                    GIVEN MIX OF CREATE AND CREATE2 DEPLOYMENTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_GivenMixedDeployments_ShouldTrackBothInSameRegistry() external {
        vm.startPrank(deployer);
        address createModule = factory.create();
        address create2Module = factory.createDeterministic(DEFAULT_SALT);
        vm.stopPrank();

        assertTrue(factory.isDeployedModule(createModule));
        assertTrue(factory.isDeployedModule(create2Module));
        assertEq(factory.getModuleCount(), 2);

        address[] memory modules = factory.getDeployedModules();
        assertEq(modules[0], createModule);
        assertEq(modules[1], create2Module);
    }
}
