// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BraleModuleBase } from "../BraleModuleBase.t.sol";

contract BraleModule_Validate_Test is BraleModuleBase {
    function _assertInvalid(uint256 amount, bytes memory params, string memory expected) internal view {
        (bool ok, string memory reason) = module.validate(address(token), amount, params);
        assertFalse(ok);
        assertEq(reason, expected);
    }

    function test_WhenAmountIsZero_ReturnsFalse() external view {
        _assertInvalid(0, _params(), "Zero amount");
    }

    function test_WhenParamsTooShort_ReturnsFalse() external view {
        _assertInvalid(1, hex"1234", "Invalid params encoding");
        _assertInvalid(1, "", "Invalid params encoding");
    }

    function test_WhenParamsAreOldTwoFieldEncoding_ReturnsFalse() external view {
        _assertInvalid(1e18, abi.encode(depositAddress, address(usdc)), "Invalid params encoding");
    }

    function test_WhenParamsHaveDirtyBits_ReturnsFalse() external view {
        _assertInvalid(
            1, abi.encode(uint256(type(uint160).max) + 1, address(usdc), uint256(1)), "Invalid params encoding"
        );
    }

    function test_WhenDepositAddressIsZero_ReturnsFalse() external view {
        _assertInvalid(1, _params(address(0), address(usdc)), "Zero deposit address");
    }

    function test_WhenDepositAddressIsPaymentRails_ReturnsFalse() external view {
        _assertInvalid(1, _params(address(paymentRails), address(usdc)), "Deposit address is PaymentRails");
    }

    function test_WhenDepositAddressIsModule_ReturnsFalse() external view {
        _assertInvalid(1, _params(address(module), address(usdc)), "Deposit address is module");
    }

    function test_WhenDepositAddressIsInputToken_ReturnsFalse() external view {
        _assertInvalid(1, _params(address(token), address(usdc)), "Deposit address is input token");
    }

    function test_WhenDepositAddressIsOutputToken_ReturnsFalse() external view {
        _assertInvalid(1, _params(address(usdc), address(usdc)), "Deposit address is output token");
    }

    function test_WhenOutputTokenIsZero_ReturnsFalse() external view {
        _assertInvalid(1, _params(depositAddress, address(0)), "Zero output token");
    }

    function test_WhenOutputTokenEqualsInputToken_ReturnsFalse() external view {
        _assertInvalid(1, _params(depositAddress, address(token)), "Output token equals input token");
    }

    function test_WhenMinAmountIsZero_ReturnsFalse() external view {
        _assertInvalid(1e18, _params(depositAddress, address(usdc), 0), "Zero minimum amount");
    }

    function test_WhenAmountBelowMinAmount_ReturnsFalse() external view {
        _assertInvalid(1e18 - 1, _params(depositAddress, address(usdc), 1e18), "Below minimum redemption");
    }

    function test_WhenAmountEqualsMinAmount_ReturnsTrue() external view {
        (bool ok,) = module.validate(address(token), 1e18, _params(depositAddress, address(usdc), 1e18));
        assertTrue(ok);
    }

    function test_WhenParamsValid_ReturnsTrue() external view {
        (bool ok, string memory reason) = module.validate(address(token), 1e18, _params());
        assertTrue(ok);
        assertEq(bytes(reason).length, 0);
    }

    function test_WhenAmountExceedsRailsBalance_StillReturnsTrue() external view {
        // Amount far above the rails balance: validate must not check balances.
        (bool ok,) = module.validate(address(token), RAILS_BALANCE * 1000, _params());
        assertTrue(ok);
    }

    function test_WhenCalledByAnyAddress_ReturnsTrue() external {
        vm.prank(attacker);
        (bool ok,) = module.validate(address(token), 1e18, _params());
        assertTrue(ok);
    }
}
