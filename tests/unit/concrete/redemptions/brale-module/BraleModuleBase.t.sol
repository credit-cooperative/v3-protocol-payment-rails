// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { BraleModule } from "../../../../../src/modules/redemptions/BraleModule.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { MockERC20 } from "../../../../shared/mocks/MockERC20.sol";
import { MockPaymentRails } from "../../../../shared/mocks/MockPaymentRails.sol";

/// @dev Base test contract for BraleModule unit tests.
abstract contract BraleModuleBase is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event RedemptionInitiated(
        bytes32 indexed redemptionId,
        address indexed token,
        address indexed depositAddress,
        uint256 nonce,
        uint256 amount,
        address paymentRails,
        address outputToken
    );
    event TokensReturned(address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    bytes32 internal constant TYPEHASH = keccak256("BraleRedemption(uint256 chainId,address module,uint256 nonce)");
    uint256 internal constant MIN_AMOUNT = 1;
    uint256 internal constant RAILS_BALANCE = 1_000_000e18;

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    BraleModule internal module;
    MockPaymentRails internal paymentRails;
    MockERC20 internal token;
    MockERC20 internal usdc;

    address internal owner;
    address internal attacker;
    address internal depositAddress;

    /*//////////////////////////////////////////////////////////////////////////
                                    SET UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        owner = makeAddr("owner");
        attacker = makeAddr("attacker");
        depositAddress = makeAddr("braleDeposit");

        paymentRails = new MockPaymentRails();
        module = new BraleModule(address(paymentRails), owner);
        paymentRails.setModule(address(module));

        token = new MockERC20("Brale SBC", "SBC");
        usdc = new MockERC20("USD Coin", "USDC");
        token.mint(address(paymentRails), RAILS_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _params() internal view returns (bytes memory) {
        return _params(depositAddress, address(usdc));
    }

    function _params(address dep, address out) internal view returns (bytes memory) {
        return _params(dep, out, MIN_AMOUNT);
    }

    function _params(address dep, address out, uint256 minAmount) internal view returns (bytes memory) {
        return module.encodeParams(
            DataTypes.BraleRedemptionParams({ depositAddress: dep, outputToken: out, minAmount: minAmount })
        );
    }

    function _execute(uint256 amount) internal returns (DataTypes.ExecutionResult memory) {
        return paymentRails.initiateSwap(address(token), amount, _params());
    }

    function _expectedId(uint256 nonce) internal view returns (bytes32) {
        return keccak256(abi.encode(TYPEHASH, block.chainid, address(module), nonce));
    }
}
