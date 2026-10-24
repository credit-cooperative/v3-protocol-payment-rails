// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaymentRailsBase } from "../PaymentRailsBase.t.sol";
import { Constants } from "../../../../../src/libraries/Constants.sol";

contract PaymentRailsGetTokenBalanceNativeTest is PaymentRailsBase {
    function test_ShouldExposeTheNativeSentinelThroughNATIVE_TOKEN() external view {
        assertEq(paymentRails.NATIVE_TOKEN(), Constants.NATIVE_TOKEN);
        assertEq(paymentRails.NATIVE_TOKEN(), 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }

    function test_WhenTokenIsNATIVE_TOKEN() external {
        _sendNative(executor, 2 ether);
        assertEq(paymentRails.getTokenBalance(NATIVE), 2 ether);

        // vm.deal models value that arrives without running receive()
        vm.deal(address(paymentRails), 5 ether);
        assertEq(paymentRails.getTokenBalance(NATIVE), 5 ether);
    }

    function test_WhenTokenIsAnERC20() external view {
        assertEq(paymentRails.getTokenBalance(address(token)), INITIAL_BALANCE);
    }
}
