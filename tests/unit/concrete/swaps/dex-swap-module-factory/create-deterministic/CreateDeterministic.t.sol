// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { DexSwapModuleFactoryBase } from "../DexSwapModuleFactoryBase.t.sol";
import { DexSwapModuleFactory } from "../../../../../../src/modules/swaps/DexSwapModuleFactory.sol";
import { DexSwapModule } from "../../../../../../src/modules/swaps/DexSwapModule.sol";

import { MockRouter } from "../../../../../shared/mocks/MockRouter.sol";

contract CreateDeterministic_DexSwapModuleFactory_Test is DexSwapModuleFactoryBase {
    function test_WhenSaltIsUnused_ShouldDeployContract() external {
        vm.prank(deployer);
        address module = factory.createDeterministic(DEFAULT_SALT);
        assertEq(DexSwapModule(module).moduleType(), "SWAP");
    }

    function test_WhenSaltIsUnused_ShouldDeployToPredictedAddress() external {
        address predicted = factory.predictDeterministicAddress(DEFAULT_SALT);
        vm.prank(deployer);
        address module = factory.createDeterministic(DEFAULT_SALT);
        assertEq(module, predicted);
    }

    function test_WhenSaltIsUnused_ShouldWireChainConfig() external {
        vm.prank(deployer);
        address module = factory.createDeterministic(DEFAULT_SALT);

        assertEq(DexSwapModule(module).router(), factory.router());
        assertEq(DexSwapModule(module).sequencerUptimeFeed(), factory.sequencerUptimeFeed());
        assertEq(DexSwapModule(module).sequencerGracePeriod(), factory.sequencerGracePeriod());
    }

    function test_WhenSaltIsUnused_ShouldRegisterModule() external {
        vm.prank(deployer);
        address module = factory.createDeterministic(DEFAULT_SALT);
        assertTrue(factory.isDeployedModule(module));
        assertEq(factory.getModuleCount(), 1);
    }

    function test_WhenSaltIsUnused_ShouldEmitEvent() external {
        address predicted = factory.predictDeterministicAddress(DEFAULT_SALT);

        vm.expectEmit(true, true, false, true);
        emit DexSwapModuleCreated(predicted, deployer);

        vm.prank(deployer);
        factory.createDeterministic(DEFAULT_SALT);
    }

    function test_RevertWhen_SameSaltReused() external {
        vm.prank(deployer);
        factory.createDeterministic(DEFAULT_SALT);

        vm.prank(deployer);
        vm.expectRevert();
        factory.createDeterministic(DEFAULT_SALT);
    }

    function test_WhenDifferentSaltsUsed_ShouldDeployToDifferentAddresses() external {
        vm.startPrank(deployer);
        address module1 = factory.createDeterministic(bytes32(uint256(1)));
        address module2 = factory.createDeterministic(bytes32(uint256(2)));
        vm.stopPrank();
        assertTrue(module1 != module2);
    }

    /// @dev The caller is not part of the CREATE2 derivation, so a salt is first-come-first-served.
    /// What matters is that whoever takes it still gets this factory's wiring — a stranger cannot
    /// occupy a predicted address with a differently-configured module.
    function test_WhenDifferentCallerUsesSameSalt_ShouldStillCarryFactoryConfig() external {
        address stranger = makeAddr("stranger");
        address predicted = factory.predictDeterministicAddress(DEFAULT_SALT);

        vm.prank(stranger);
        address module = factory.createDeterministic(DEFAULT_SALT);

        assertEq(module, predicted);
        assertEq(DexSwapModule(module).router(), factory.router());
        assertEq(DexSwapModule(module).sequencerUptimeFeed(), factory.sequencerUptimeFeed());
    }

    /// @dev Constructor arguments are part of the CREATE2 derivation, so two factories with different
    /// routers cannot collide on a shared salt.
    function test_WhenFactoriesHaveDifferentRouters_ShouldDeployToDifferentAddresses() external {
        MockRouter otherRouter = new MockRouter();
        DexSwapModuleFactory otherFactory = new DexSwapModuleFactory(address(otherRouter), address(0), 0);

        vm.startPrank(deployer);
        address module1 = factory.createDeterministic(DEFAULT_SALT);
        address module2 = otherFactory.createDeterministic(DEFAULT_SALT);
        vm.stopPrank();

        assertTrue(module1 != module2);
        assertEq(DexSwapModule(module1).router(), address(router));
        assertEq(DexSwapModule(module2).router(), address(otherRouter));
    }

    function testFuzz_PredictedAddressMatchesActual(bytes32 fuzzSalt) external {
        address predicted = factory.predictDeterministicAddress(fuzzSalt);

        vm.prank(deployer);
        address actual = factory.createDeterministic(fuzzSalt);

        assertEq(actual, predicted);
    }
}
