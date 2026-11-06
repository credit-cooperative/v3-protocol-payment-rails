// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BraleModuleBase } from "../BraleModuleBase.t.sol";

contract BraleModule_ModuleType_Test is BraleModuleBase {
    function test_WhenCalled_ReturnsBraleRedemption() external view {
        assertEq(module.moduleType(), "BRALE_REDEMPTION");
    }

    function test_WhenCalled_IsNonEmpty() external view {
        assertTrue(bytes(module.moduleType()).length > 0);
    }
}
