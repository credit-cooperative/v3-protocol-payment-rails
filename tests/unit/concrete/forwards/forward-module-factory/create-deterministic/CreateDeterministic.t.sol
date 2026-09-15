// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ForwardModuleFactoryBase } from "../ForwardModuleFactoryBase.t.sol";
import { ForwardModule } from "../../../../../../src/modules/forwards/ForwardModule.sol";

contract CreateDeterministic_ForwardModuleFactory_Test is ForwardModuleFactoryBase {
    function test_WhenSaltIsUnused_ShouldDeployContract() external {
        vm.prank(deployer);
        address module = factory.createDeterministic(DEFAULT_SALT);
        assertEq(ForwardModule(module).moduleType(), "FORWARD");
    }

    function test_WhenSaltIsUnused_ShouldDeployToPredictedAddress() external {
        address predicted = factory.predictDeterministicAddress(DEFAULT_SALT);
        vm.prank(deployer);
        address module = factory.createDeterministic(DEFAULT_SALT);
        assertEq(module, predicted);
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
        emit ForwardModuleCreated(predicted, deployer);

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
    /// Since every module the factory deploys is identical and holds no privileged role, a taken salt
    /// costs a deployment, not safety — this pins that behavior so it is not mistaken for a reservation.
    function test_WhenDifferentCallerUsesSameSalt_ShouldOccupySameAddress() external {
        address other = makeAddr("other");
        address predicted = factory.predictDeterministicAddress(DEFAULT_SALT);

        vm.prank(other);
        address module = factory.createDeterministic(DEFAULT_SALT);
        assertEq(module, predicted);

        vm.prank(deployer);
        vm.expectRevert();
        factory.createDeterministic(DEFAULT_SALT);
    }

    function testFuzz_PredictedAddressMatchesActual(bytes32 fuzzSalt) external {
        address predicted = factory.predictDeterministicAddress(fuzzSalt);

        vm.prank(deployer);
        address actual = factory.createDeterministic(fuzzSalt);

        assertEq(actual, predicted);
    }
}
