// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { WrapModule } from "../../../../../src/modules/native/WrapModule.sol";
import { Constants } from "../../../../../src/libraries/Constants.sol";
import { MockWETH9 } from "../../../../shared/mocks/MockWETH9.sol";
import { MockERC20 } from "../../../../shared/mocks/MockERC20.sol";

abstract contract WrapModuleBase is Test {
    event Wrapped(address indexed paymentRails, uint256 amount);

    uint256 internal constant DEFAULT_AMOUNT = 1 ether;
    address internal constant NATIVE = Constants.NATIVE_TOKEN;

    WrapModule internal module;
    MockWETH9 internal weth;
    MockERC20 internal token;
    address internal paymentRails;

    function setUp() public virtual {
        paymentRails = makeAddr("paymentRails");
        weth = new MockWETH9();
        token = new MockERC20("Test Token", "TST");
        module = new WrapModule(address(weth));
        vm.deal(paymentRails, 100 ether);
    }
}
