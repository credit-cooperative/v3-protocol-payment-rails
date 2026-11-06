// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { PaymentRails } from "../../../../src/core/PaymentRails.sol";
import { BraleModule } from "../../../../src/modules/redemptions/BraleModule.sol";
import { BraleModuleFactory } from "../../../../src/modules/redemptions/BraleModuleFactory.sol";
import { DataTypes } from "../../../../src/types/DataTypes.sol";
import { BraleModuleHandler } from "./BraleModuleHandler.sol";
import { MockERC20 } from "../../../shared/mocks/MockERC20.sol";

/// @title BraleModuleInvariant
/// @notice Stateful fuzz tests: the module never holds funds, nonce tracks successes, the deposit address
///         receives exactly what was redeemed, and no allowance is left behind.
contract BraleModuleInvariant is Test {
    PaymentRails internal rails;
    BraleModule internal module;
    BraleModuleHandler internal handler;
    MockERC20 internal token;
    MockERC20 internal usdc;
    address internal depositAddress;

    function setUp() public {
        depositAddress = makeAddr("braleDeposit");
        rails = new PaymentRails(address(this));
        BraleModuleFactory factory = new BraleModuleFactory(address(this));
        module = BraleModule(factory.create(address(this), address(rails)));
        token = new MockERC20("Brale SBC", "SBC");
        usdc = new MockERC20("USD Coin", "USDC");

        bytes memory params = module.encodeParams(
            DataTypes.BraleRedemptionParams({
                depositAddress: depositAddress, outputToken: address(usdc), minAmount: 1
            })
        );
        rails.configureToken(address(token), "BRALE_REDEMPTION", address(module), 1, params, true);

        handler = new BraleModuleHandler(rails, module, token);
        targetContract(address(handler));

        excludeContract(address(module));
        excludeContract(address(rails));
        excludeContract(address(token));
        excludeContract(address(usdc));
        excludeContract(address(factory));
    }

    /// @notice INV-1: the module never holds the token.
    function invariant_ModuleHoldsNoTokens() public view {
        assertEq(token.balanceOf(address(module)), 0);
    }

    /// @notice INV-2: the nonce equals the number of successful redemptions.
    function invariant_NonceEqualsSuccessCount() public view {
        assertEq(module.redemptionNonce(), handler.ghost_successCount());
    }

    /// @notice INV-3: the deposit address holds exactly the redeemed total.
    function invariant_DepositEqualsTotalRedeemed() public view {
        assertEq(token.balanceOf(depositAddress), handler.ghost_totalRedeemed());
    }

    /// @notice INV-4: the rails never leaves an allowance to the module.
    function invariant_NoResidualAllowance() public view {
        assertEq(token.allowance(address(rails), address(module)), 0);
    }
}
