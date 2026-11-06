// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { Vm } from "forge-std/src/Vm.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { BraleModule } from "../../../../../src/modules/redemptions/BraleModule.sol";
import { BraleModuleFactory } from "../../../../../src/modules/redemptions/BraleModuleFactory.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { MockERC20 } from "../../../../shared/mocks/MockERC20.sol";
import { FeeOnTransferERC20 } from "../../../../shared/mocks/FeeOnTransferERC20.sol";
import { SenderFeeERC20 } from "../../../../shared/mocks/SenderFeeERC20.sol";

contract BraleModuleIntegrationTest is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event ActionExecuted(
        address indexed token,
        string actionType,
        uint256 amountIn,
        uint256 amountOut,
        address outputToken,
        address indexed executor
    );
    event ActionFailed(
        address indexed token, string actionType, uint256 amount, string reason, address indexed executor
    );
    event RedemptionInitiated(
        bytes32 indexed redemptionId,
        address indexed token,
        address indexed depositAddress,
        uint256 nonce,
        uint256 amount,
        address paymentRails,
        address outputToken
    );

    /*//////////////////////////////////////////////////////////////////////////
                                    STATE
    //////////////////////////////////////////////////////////////////////////*/

    uint256 internal constant MIN_BALANCE = 1e18;
    uint256 internal constant AMOUNT = 100e18;
    string internal constant ACTION = "BRALE_REDEMPTION";

    PaymentRails internal rails;
    BraleModuleFactory internal factory;
    BraleModule internal module;
    MockERC20 internal token;
    MockERC20 internal usdc;

    address internal railsOwner;
    address internal moduleOwner;
    address internal keeper;
    address internal deposit;

    function setUp() public {
        railsOwner = makeAddr("railsOwner");
        moduleOwner = makeAddr("moduleOwner");
        keeper = makeAddr("keeper");
        deposit = makeAddr("braleDeposit");

        rails = new PaymentRails(railsOwner);
        factory = new BraleModuleFactory(address(this));
        module = BraleModule(factory.create(moduleOwner, address(rails)));

        token = new MockERC20("Brale SBC", "SBC");
        usdc = new MockERC20("USD Coin", "USDC");

        _configure(rails, address(token), address(module), deposit);
        token.mint(address(rails), AMOUNT * 10);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _params(BraleModule m, address dep) internal view returns (bytes memory) {
        return m.encodeParams(
            DataTypes.BraleRedemptionParams({ depositAddress: dep, outputToken: address(usdc), minAmount: MIN_BALANCE })
        );
    }

    function _configure(PaymentRails r, address tkn, address m, address dep) internal {
        bytes memory params = _params(BraleModule(m), dep);
        vm.prank(railsOwner);
        r.configureToken(tkn, ACTION, m, MIN_BALANCE, params, true);
    }

    function _id(BraleModule m, uint256 nonce) internal view returns (bytes32) {
        return keccak256(abi.encode(m.REDEMPTION_ID_TYPEHASH(), block.chainid, address(m), nonce));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_WhenKeeperExecutes_RedeemsToDepositAddress() external {
        vm.expectEmit(true, true, true, true, address(module));
        emit RedemptionInitiated(_id(module, 0), address(token), deposit, 0, AMOUNT, address(rails), address(usdc));
        vm.expectEmit(true, false, true, true, address(rails));
        emit ActionExecuted(address(token), ACTION, AMOUNT, 0, address(usdc), keeper);

        vm.prank(keeper);
        bool ok = rails.executeAction(address(token), AMOUNT);

        assertTrue(ok);
        assertEq(token.balanceOf(deposit), AMOUNT);
        assertEq(token.balanceOf(address(rails)), AMOUNT * 9);
        assertEq(token.allowance(address(rails), address(module)), 0);
        assertEq(token.balanceOf(address(module)), 0);
        assertEq(module.redemptionNonce(), 1);
    }

    function test_WhenExecutedRepeatedly_NoncesAndIdsAreUnique() external {
        bytes32[3] memory ids;
        for (uint256 i; i < 3; ++i) {
            vm.recordLogs();
            vm.prank(keeper);
            assertTrue(rails.executeAction(address(token), AMOUNT));
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].emitter == address(module)) {
                    ids[i] = logs[j].topics[1];
                    (uint256 nonce,,,) = abi.decode(logs[j].data, (uint256, uint256, address, address));
                    assertEq(nonce, i);
                }
            }
            assertEq(ids[i], _id(module, i));
        }
        assertTrue(ids[0] != ids[1] && ids[1] != ids[2] && ids[0] != ids[2]);
        assertEq(token.balanceOf(deposit), AMOUNT * 3);
        assertEq(token.balanceOf(address(module)), 0);
    }

    function test_WhenTokenChargesRecipientFee_ActionFailsWithoutEffects() external {
        FeeOnTransferERC20 fot = new FeeOnTransferERC20();
        fot.mint(address(rails), AMOUNT);
        _configure(rails, address(fot), address(module), deposit);

        vm.expectEmit(true, false, true, true, address(rails));
        emit ActionFailed(address(fot), ACTION, AMOUNT, "Module execution reverted", keeper);
        vm.prank(keeper);
        bool ok = rails.executeAction(address(fot), AMOUNT);

        assertFalse(ok);
        assertEq(fot.balanceOf(address(rails)), AMOUNT);
        assertEq(fot.balanceOf(deposit), 0);
        assertEq(fot.balanceOf(address(module)), 0);
        assertEq(module.redemptionNonce(), 0);
    }

    function test_WhenTokenChargesSenderFee_ActionFailsWithoutEffects() external {
        SenderFeeERC20 sfee = new SenderFeeERC20();
        sfee.mint(address(rails), AMOUNT * 2);
        _configure(rails, address(sfee), address(module), deposit);

        vm.expectEmit(true, false, true, true, address(rails));
        emit ActionFailed(address(sfee), ACTION, AMOUNT, "Module execution reverted", keeper);
        vm.prank(keeper);
        bool ok = rails.executeAction(address(sfee), AMOUNT);

        assertFalse(ok);
        assertEq(sfee.balanceOf(address(rails)), AMOUNT * 2);
        assertEq(sfee.balanceOf(deposit), 0);
        assertEq(module.redemptionNonce(), 0);
    }

    function test_WhenDepositAddressIsRails_ActionFailsWithReason() external {
        _configure(rails, address(token), address(module), address(rails));

        vm.expectEmit(true, false, true, true, address(rails));
        emit ActionFailed(address(token), ACTION, AMOUNT, "Deposit address is PaymentRails", keeper);
        vm.prank(keeper);
        bool ok = rails.executeAction(address(token), AMOUNT);

        assertFalse(ok);
        assertEq(module.redemptionNonce(), 0);
        assertEq(token.balanceOf(address(rails)), AMOUNT * 10);
    }

    function test_WhenPreviewExecution_ReturnsParEstimate() external view {
        (uint256 est, address out) = rails.previewExecution(address(token));
        assertEq(est, AMOUNT * 10);
        assertEq(out, address(usdc));
    }

    function test_WhenDepositAddressReconfigured_NextRedemptionGoesToNewAddress() external {
        address newDeposit = makeAddr("newDeposit");

        vm.prank(keeper);
        assertTrue(rails.executeAction(address(token), AMOUNT));

        _configure(rails, address(token), address(module), newDeposit);
        vm.prank(keeper);
        assertTrue(rails.executeAction(address(token), AMOUNT));

        assertEq(token.balanceOf(deposit), AMOUNT);
        assertEq(token.balanceOf(newDeposit), AMOUNT);
        assertEq(token.balanceOf(address(module)), 0);
    }

    function test_RevertWhen_EoaCallsModuleDirectly() external {
        bytes memory params = _params(module, deposit);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Errors.BraleModule_NotPaymentRails.selector, keeper, address(rails)));
        module.execute(address(token), AMOUNT, params);
    }

    function test_WhenTwoBorrowers_RedemptionsAreSeparated() external {
        PaymentRails rails2 = new PaymentRails(railsOwner);
        BraleModule module2 = BraleModule(factory.create(moduleOwner, address(rails2)));
        address deposit2 = makeAddr("braleDeposit2");
        _configure(rails2, address(token), address(module2), deposit2);
        token.mint(address(rails2), AMOUNT * 10);

        vm.prank(keeper);
        assertTrue(rails.executeAction(address(token), AMOUNT));
        vm.prank(keeper);
        assertTrue(rails2.executeAction(address(token), AMOUNT * 2));

        assertEq(token.balanceOf(deposit), AMOUNT);
        assertEq(token.balanceOf(deposit2), AMOUNT * 2);
        assertEq(token.balanceOf(address(rails)), AMOUNT * 9);
        assertEq(token.balanceOf(address(rails2)), AMOUNT * 8);
        assertEq(token.balanceOf(address(module)), 0);
        assertEq(token.balanceOf(address(module2)), 0);

        assertEq(module.paymentRails(), address(rails));
        assertEq(module2.paymentRails(), address(rails2));
        assertTrue(_id(module, 0) != _id(module2, 0));
        assertEq(module.computeRedemptionId(0), _id(module, 0));
        assertEq(module2.computeRedemptionId(0), _id(module2, 0));
    }
}
