// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { UnwrapModule } from "../../../../../src/modules/native/UnwrapModule.sol";
import { Constants } from "../../../../../src/libraries/Constants.sol";
import { MockWETH9 } from "../../../../shared/mocks/MockWETH9.sol";
import { MockERC20 } from "../../../../shared/mocks/MockERC20.sol";

/// @dev Caller with no receive(): the module cannot hand native value back to it.
contract NoReceiveCaller {
    function callExecute(UnwrapModule module, address token, uint256 amount) external returns (bool) {
        return module.execute(token, amount, "").success;
    }
}

/// @dev The test contract is the PaymentRails stand-in, so it must be able to take native value.
abstract contract UnwrapModuleBase is Test {
    event Unwrapped(address indexed paymentRails, uint256 amount);

    uint256 internal constant DEFAULT_AMOUNT = 1 ether;
    address internal constant NATIVE = Constants.NATIVE_TOKEN;

    UnwrapModule internal module;
    MockWETH9 internal weth;
    MockERC20 internal token;

    function setUp() public virtual {
        weth = new MockWETH9();
        token = new MockERC20("Test Token", "TST");
        module = new UnwrapModule(address(weth));

        vm.deal(address(this), 100 ether);
        weth.deposit{ value: 50 ether }();
        weth.approve(address(module), type(uint256).max);
    }

    /// @dev The rail-side entry the module returns value through.
    function returnNative(address) external payable { }

    receive() external payable { }
}
