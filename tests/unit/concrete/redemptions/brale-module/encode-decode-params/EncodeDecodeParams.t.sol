// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BraleModuleBase } from "../BraleModuleBase.t.sol";
import { DataTypes } from "../../../../../../src/types/DataTypes.sol";

contract BraleModule_EncodeDecodeParams_Test is BraleModuleBase {
    function test_WhenEncodedAndDecoded_RoundTrips() external view {
        bytes memory enc = _params();
        assertEq(enc.length, 96);
        DataTypes.BraleRedemptionParams memory d = module.decodeParams(enc);
        assertEq(d.depositAddress, depositAddress);
        assertEq(d.outputToken, address(usdc));
        assertEq(d.minAmount, MIN_AMOUNT);
    }

    function testFuzz_WhenEncodedAndDecoded_RoundTrips(address dep, address out, uint256 minAmt) external view {
        DataTypes.BraleRedemptionParams memory d = module.decodeParams(_params(dep, out, minAmt));
        assertEq(d.depositAddress, dep);
        assertEq(d.outputToken, out);
        assertEq(d.minAmount, minAmt);
    }

    function test_RevertWhen_DecodingShortBytes() external {
        vm.expectRevert();
        module.decodeParams(hex"1234");
    }
}
