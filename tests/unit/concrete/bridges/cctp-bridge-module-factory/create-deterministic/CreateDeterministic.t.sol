// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { CCTPBridgeModuleFactoryBase } from "../CCTPBridgeModuleFactoryBase.t.sol";
import { CCTPBridgeModuleFactory } from "../../../../../../src/modules/bridges/CCTPBridgeModuleFactory.sol";
import { CCTPBridgeModule } from "../../../../../../src/modules/bridges/CCTPBridgeModule.sol";

import { MockERC20 } from "../../../../../shared/mocks/MockERC20.sol";

contract CreateDeterministic_CCTPBridgeModuleFactory_Test is CCTPBridgeModuleFactoryBase {
    function test_WhenSaltIsUnused_ShouldDeployContract() external {
        vm.prank(deployer);
        address module = factory.createDeterministic(DEFAULT_SALT);
        assertEq(CCTPBridgeModule(module).moduleType(), "CCTP_BRIDGE");
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

        assertEq(CCTPBridgeModule(module).tokenMessenger(), factory.tokenMessenger());
        assertEq(CCTPBridgeModule(module).usdc(), factory.usdc());
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
        emit CCTPBridgeModuleCreated(predicted, deployer);

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
    /// occupy a predicted address with a module pointed at a counterfeit token or messenger.
    function test_WhenDifferentCallerUsesSameSalt_ShouldStillCarryFactoryConfig() external {
        address stranger = makeAddr("stranger");
        address predicted = factory.predictDeterministicAddress(DEFAULT_SALT);

        vm.prank(stranger);
        address module = factory.createDeterministic(DEFAULT_SALT);

        assertEq(module, predicted);
        assertEq(CCTPBridgeModule(module).tokenMessenger(), address(tokenMessenger));
        assertEq(CCTPBridgeModule(module).usdc(), address(usdc));
    }

    /// @dev Constructor arguments are part of the CREATE2 derivation, so two factories with different
    /// USDC addresses cannot collide on a shared salt.
    function test_WhenFactoriesHaveDifferentUsdc_ShouldDeployToDifferentAddresses() external {
        MockERC20 otherUsdc = new MockERC20("Other USD Coin", "USDC");
        CCTPBridgeModuleFactory otherFactory = new CCTPBridgeModuleFactory(address(tokenMessenger), address(otherUsdc));

        vm.startPrank(deployer);
        address module1 = factory.createDeterministic(DEFAULT_SALT);
        address module2 = otherFactory.createDeterministic(DEFAULT_SALT);
        vm.stopPrank();

        assertTrue(module1 != module2);
        assertEq(CCTPBridgeModule(module1).usdc(), address(usdc));
        assertEq(CCTPBridgeModule(module2).usdc(), address(otherUsdc));
    }

    function testFuzz_PredictedAddressMatchesActual(bytes32 fuzzSalt) external {
        address predicted = factory.predictDeterministicAddress(fuzzSalt);

        vm.prank(deployer);
        address actual = factory.createDeterministic(fuzzSalt);

        assertEq(actual, predicted);
    }
}
