// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { NativeForwardModule } from "../../../../../src/modules/native/NativeForwardModule.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Constants } from "../../../../../src/libraries/Constants.sol";
import { MockERC20 } from "../../../../shared/mocks/MockERC20.sol";

abstract contract NativeForwardModuleBase is Test {
    event NativeForwarded(address indexed paymentRails, address indexed recipient, uint256 amount);

    uint256 internal constant DEFAULT_AMOUNT = 1 ether;
    uint256 internal constant DEFAULT_MIN_AMOUNT = 0.1 ether;
    address internal constant NATIVE = Constants.NATIVE_TOKEN;

    NativeForwardModule internal module;
    MockERC20 internal token;
    address internal paymentRails;
    address internal recipient;

    function setUp() public virtual {
        paymentRails = makeAddr("paymentRails");
        recipient = makeAddr("recipient");
        module = new NativeForwardModule();
        token = new MockERC20("Test Token", "TST");
        vm.deal(paymentRails, 100 ether);
    }

    function _params(address to, uint256 minAmount) internal view returns (bytes memory) {
        return module.encodeParams(DataTypes.ForwardParams({ recipient: to, minAmount: minAmount }));
    }
}
