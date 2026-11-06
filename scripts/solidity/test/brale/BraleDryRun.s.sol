// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { Script, console2 } from "forge-std/src/Script.sol";
import { StdCheats } from "forge-std/src/StdCheats.sol";
import { Vm } from "forge-std/src/Vm.sol";
import { PaymentRails } from "../../../../src/core/PaymentRails.sol";
import { BraleModule } from "../../../../src/modules/redemptions/BraleModule.sol";
import { BraleModuleFactory } from "../../../../src/modules/redemptions/BraleModuleFactory.sol";
import { DataTypes } from "../../../../src/types/DataTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "../../../../tests/shared/mocks/MockERC20.sol";

/// @title BraleDryRun
/// @author Credit Cooperative
/// @notice Offline end-to-end simulation: deploy rails + factory + module, configure, fund, execute, then print
///         the redemptionId and the UUIDv8 Idempotency-Key (the reference vector for the off-chain service).
/// @dev Simulation-only. Runs with no env. Optional env: BRALE_TOKEN, BRALE_DEPOSIT_ADDRESS, OUTPUT_TOKEN,
///      AMOUNT, MIN_BALANCE. When BRALE_TOKEN is set (fork run) the token is funded with `deal`.
///
///      Usage: forge script scripts/solidity/test/brale/BraleDryRun.s.sol -vvv
contract BraleDryRun is Script, StdCheats {
    bytes32 internal constant REDEMPTION_INITIATED_TOPIC =
        keccak256("RedemptionInitiated(bytes32,address,address,uint256,uint256,address,address)");

    struct Ctx {
        address token;
        address depositAddress;
        address outputToken;
        uint256 amount;
        uint256 minBalance;
        uint256 minAmount;
        PaymentRails rails;
        BraleModule module;
    }

    /// @dev True when the token is a script-deployed mock (BRALE_TOKEN unset).
    bool internal mockToken = true;

    function run() public {
        Ctx memory c;
        c.token = vm.envOr("BRALE_TOKEN", address(0));
        c.depositAddress = vm.envOr("BRALE_DEPOSIT_ADDRESS", makeAddr("braleDeposit"));
        c.outputToken = vm.envOr("OUTPUT_TOKEN", address(0));
        c.amount = vm.envOr("AMOUNT", uint256(100e18));
        c.minBalance = vm.envOr("MIN_BALANCE", uint256(0));
        // Input-token base units; must be nonzero and at or below AMOUNT. Default: 1 whole 18-dec token.
        c.minAmount = vm.envOr("MIN_AMOUNT", uint256(1e18));

        _deployAndConfigure(c);
        (bytes32 redemptionId, uint256 nonce) = _executeAndCheck(c);

        console2.log("=============================================================");
        console2.log("  Brale Dry Run");
        console2.log("=============================================================");
        console2.log("PaymentRails:  ", address(c.rails));
        console2.log("BraleModule:   ", address(c.module));
        console2.log("Token:         ", c.token);
        console2.log("Deposit:       ", c.depositAddress);
        console2.log("Output token:  ", c.outputToken);
        console2.log("Amount:        ", c.amount);
        console2.log("chainId:       ", block.chainid);
        console2.log("nonce:         ", nonce);
        console2.log("redemptionId:  ", vm.toString(redemptionId));
        console2.log("Idempotency-Key (UUIDv8):", _toUuidV8(redemptionId));
        console2.log("=============================================================");
    }

    function _deployAndConfigure(Ctx memory c) internal {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        if (c.token == address(0)) c.token = address(new MockERC20("Brale SBC", "SBC"));
        else mockToken = false;
        if (c.outputToken == address(0)) c.outputToken = address(new MockERC20("USD Coin", "USDC"));

        c.rails = new PaymentRails(deployer);
        BraleModuleFactory factory = new BraleModuleFactory(deployer);
        c.module = BraleModule(factory.create(deployer, address(c.rails)));

        bytes memory params = c.module
            .encodeParams(
                DataTypes.BraleRedemptionParams({
                    depositAddress: c.depositAddress, outputToken: c.outputToken, minAmount: c.minAmount
                })
            );
        c.rails.configureToken(c.token, "BRALE_REDEMPTION", address(c.module), c.minBalance, params, true);

        if (mockToken) MockERC20(c.token).mint(address(c.rails), c.amount);
        else deal(c.token, address(c.rails), c.amount);
        vm.stopPrank();
    }

    function _executeAndCheck(Ctx memory c) internal returns (bytes32 redemptionId, uint256 nonce) {
        uint256 depositBefore = IERC20(c.token).balanceOf(c.depositAddress);

        vm.recordLogs();
        bool ok = c.rails.executeAction(c.token, c.amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        require(ok, "executeAction returned false");
        require(IERC20(c.token).balanceOf(c.depositAddress) - depositBefore == c.amount, "deposit delta mismatch");
        require(IERC20(c.token).balanceOf(address(c.module)) == 0, "module holds funds");

        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(c.module) && logs[i].topics[0] == REDEMPTION_INITIATED_TOPIC) {
                redemptionId = logs[i].topics[1];
                (nonce,,,) = abi.decode(logs[i].data, (uint256, uint256, address, address));
            }
        }
        require(redemptionId != bytes32(0), "RedemptionInitiated not found");
        require(redemptionId == c.module.computeRedemptionId(nonce), "id mismatch");
    }

    /// @dev README section 9: take the first 16 bytes, set version 8 and the RFC 9562 variant, format 8-4-4-4-12.
    function _toUuidV8(bytes32 id) internal pure returns (string memory) {
        bytes16 b = bytes16(id);
        uint128 v = uint128(b);
        // Byte 6 (bits 79..72 counting from the least significant end): high nibble = 0x8.
        v = (v & ~(uint128(0xf0) << 72)) | (uint128(0x80) << 72);
        // Byte 8 (bits 63..56): top two bits = 0b10.
        v = (v & ~(uint128(0xc0) << 56)) | (uint128(0x80) << 56);

        bytes memory hexChars = "0123456789abcdef";
        bytes memory out = new bytes(36);
        uint256 o;
        for (uint256 i; i < 16; ++i) {
            if (i == 4 || i == 6 || i == 8 || i == 10) out[o++] = "-";
            uint8 byteVal = uint8(v >> (8 * (15 - i)));
            out[o++] = hexChars[byteVal >> 4];
            out[o++] = hexChars[byteVal & 0x0f];
        }
        return string(out);
    }
}
