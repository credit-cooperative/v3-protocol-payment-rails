// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BraleModuleBase } from "../BraleModuleBase.t.sol";
import { BraleModule } from "../../../../../../src/modules/redemptions/BraleModule.sol";

contract BraleModule_ComputeRedemptionId_Test is BraleModuleBase {
    function test_WhenCalled_EqualsLocalRecompute() external view {
        assertEq(module.computeRedemptionId(0), _expectedId(0));
        assertEq(module.computeRedemptionId(42), _expectedId(42));
    }

    function testFuzz_WhenNoncesDiffer_IdsDiffer(uint256 n1, uint256 n2) external view {
        vm.assume(n1 != n2);
        assertTrue(module.computeRedemptionId(n1) != module.computeRedemptionId(n2));
    }

    function test_WhenChainIdChanges_IdChanges() external {
        bytes32 before = module.computeRedemptionId(1);
        vm.chainId(block.chainid + 1);
        assertTrue(module.computeRedemptionId(1) != before);
        assertEq(module.computeRedemptionId(1), _expectedId(1));
    }

    function test_WhenTwoModules_IdsDiffer() external {
        BraleModule other = new BraleModule(address(paymentRails), owner);
        assertTrue(other.computeRedemptionId(0) != module.computeRedemptionId(0));
    }

    function test_TypehashEqualsLiteralKeccak() external view {
        assertEq(
            module.REDEMPTION_ID_TYPEHASH(), keccak256("BraleRedemption(uint256 chainId,address module,uint256 nonce)")
        );
    }
}
