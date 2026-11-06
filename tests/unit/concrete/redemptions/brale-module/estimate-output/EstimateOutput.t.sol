// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BraleModuleBase } from "../BraleModuleBase.t.sol";
import { MockERC20Decimals } from "../../../../../shared/mocks/MockERC20Decimals.sol";

/// @dev Reports an out-of-range decimals value.
contract BadDecimalsToken {
    function decimals() external pure returns (uint256) {
        return 300;
    }
}

/// @dev Returns valid decimals (6) followed by 64 KB of junk returndata.
contract BombDecimalsToken {
    fallback() external {
        assembly {
            mstore(0, 6)
            return(0, 65536)
        }
    }
}

/// @dev Has code but no decimals() function.
contract NoDecimalsToken {
    fallback() external {
        revert();
    }
}

contract BraleModule_EstimateOutput_Test is BraleModuleBase {
    function _est(address tokenIn, address out, uint256 amount) internal view returns (uint256 v, address o) {
        return module.estimateOutput(tokenIn, amount, _params(depositAddress, out));
    }

    function test_WhenParamsInvalid_ReturnsZeroAndInputToken() external view {
        (uint256 v, address o) = module.estimateOutput(address(token), 0, _params());
        assertEq(v, 0);
        assertEq(o, address(token));

        (v, o) = module.estimateOutput(address(token), 1e18, hex"1234");
        assertEq(v, 0);
        assertEq(o, address(token));
    }

    function test_WhenSameDecimals_ReturnsAmount() external view {
        (uint256 v, address o) = _est(address(token), address(usdc), 123e18);
        assertEq(v, 123e18);
        assertEq(o, address(usdc));
    }

    function test_WhenOutputHasFewerDecimals_Divides() external {
        MockERC20Decimals usdc6 = new MockERC20Decimals("USDC", "USDC", 6);
        (uint256 v, address o) = _est(address(token), address(usdc6), 123e18 + 5);
        assertEq(v, 123e6);
        assertEq(o, address(usdc6));
    }

    function test_WhenOutputHasMoreDecimals_Multiplies() external {
        MockERC20Decimals in6 = new MockERC20Decimals("SBC6", "SBC6", 6);
        (uint256 v, address o) = _est(address(in6), address(usdc), 5e6);
        assertEq(v, 5e18);
        assertEq(o, address(usdc));
    }

    function test_WhenMultiplicationOverflows_ReturnsZero() external {
        MockERC20Decimals in6 = new MockERC20Decimals("SBC6", "SBC6", 6);
        (uint256 v, address o) = _est(address(in6), address(usdc), type(uint256).max);
        assertEq(v, 0);
        assertEq(o, address(usdc));
    }

    function test_WhenOutputTokenHasNoCode_ReturnsZero() external {
        address eoa = makeAddr("noCode");
        (uint256 v, address o) = _est(address(token), eoa, 1e18);
        assertEq(v, 0);
        assertEq(o, eoa);
    }

    function test_WhenDecimalsOutOfRange_ReturnsZero() external {
        BadDecimalsToken bad = new BadDecimalsToken();
        (uint256 v, address o) = _est(address(token), address(bad), 1e18);
        assertEq(v, 0);
        assertEq(o, address(bad));
    }

    function test_WhenDecimalsReturndataIsHuge_ReadsFirstWord() external {
        BombDecimalsToken bomb = new BombDecimalsToken();
        (uint256 v, address o) = _est(address(token), address(bomb), 1e18);
        assertEq(v, 1e6); // 18 -> 6 decimals
        assertEq(o, address(bomb));
    }

    function test_WhenTokenHasNoDecimals_ReturnsZero() external {
        NoDecimalsToken nd = new NoDecimalsToken();
        (uint256 v, address o) = _est(address(token), address(nd), 1e18);
        assertEq(v, 0);
        assertEq(o, address(nd));
    }

    function testFuzz_WhenOutputHasFewerDecimals_Truncates(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        MockERC20Decimals usdc6 = new MockERC20Decimals("USDC", "USDC", 6);
        (uint256 v,) = _est(address(token), address(usdc6), amount);
        assertEq(v, amount / 1e12);
    }
}
