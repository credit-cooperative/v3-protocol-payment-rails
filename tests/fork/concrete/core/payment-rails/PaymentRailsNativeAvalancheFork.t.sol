// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { PaymentRailsFactory } from "../../../../../src/core/PaymentRailsFactory.sol";
import { DexSwapModule } from "../../../../../src/modules/swaps/DexSwapModule.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { StipendSender } from "../../../../shared/mocks/NativeMocks.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface IWAVAX {
    function deposit() external payable;
}

/// @notice Avalanche C-Chain fork tests for native AVAX on PaymentRails.
/// @dev Tree: tests/fork/concrete/core/payment-rails/paymentRailsNativeAvalancheFork.tree
///
/// Raw AVAX in through call and the 2300-gas stipend on the live chain's gas schedule, owner-only sweep out,
/// and a WAVAX token route through the real SwapRouter02 with live Chainlink feeds running beside held native.
/// `vm.deal` only funds the senders.
contract PaymentRailsNativeAvalancheForkTest is Test {
    /*//////////////////////////////////////////////////////////////////////////
                            AVALANCHE C-CHAIN CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    address internal constant SWAP_ROUTER_02 = 0xbb00FF08d01D300023C629E8fFfFcb65A5a578cE;
    address internal constant USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address internal constant AVAX_USD_FEED = 0x0A77230d17318075983913bC2145DB16C7366156;
    address internal constant USDC_USD_FEED = 0xF096872672F44d6EBA71458D74fe67F9a77a23B9;

    /// @dev USDC/USD on Avalanche has a 24h heartbeat with observed gaps just over it.
    uint256 internal constant ORACLE_MAX_STALENESS = 90_000;
    uint256 internal constant DEFAULT_DEADLINE_SECONDS = 600;
    uint16 internal constant SLIPPAGE_BPS = 300;
    uint24 internal constant FEE_LOW = 500;

    uint256 internal constant AVAX_IN = 1 ether;

    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event NativeReceived(address indexed sender, uint256 amount);
    event NativeSwept(address indexed recipient, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    PaymentRails internal paymentRails;
    StipendSender internal coordinator;

    address internal owner;
    address internal keeper;
    address internal sender;

    /*//////////////////////////////////////////////////////////////////////////
                                    SETUP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public {
        string memory rpcUrl = vm.envOr("AVALANCHE_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork("avalanche");

        owner = makeAddr("owner");
        keeper = makeAddr("keeper");
        sender = makeAddr("sender");

        paymentRails = new PaymentRails(owner);
        coordinator = new StipendSender();

        vm.deal(sender, 100 ether);
        vm.deal(address(coordinator), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_WhenAvaxIsSentWithCall() external {
        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit NativeReceived(sender, AVAX_IN);

        vm.prank(sender);
        (bool ok,) = address(paymentRails).call{ value: AVAX_IN }("");

        assertTrue(ok, "raw AVAX transfer must be accepted");
        assertEq(address(paymentRails).balance, AVAX_IN);
    }

    function test_WhenAvaxIsSentWithTransfer() external {
        // transfer() forwards only the 2300-gas stipend
        coordinator.sendWithTransfer(payable(address(paymentRails)), AVAX_IN);

        assertEq(address(paymentRails).balance, AVAX_IN);
    }

    function test_WhenTheOwnerSweeps() external {
        _sendAvax(AVAX_IN);
        coordinator.sendWithTransfer(payable(address(paymentRails)), AVAX_IN);
        address exitRecipient = makeAddr("exitRecipient");

        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit NativeSwept(exitRecipient, 2 * AVAX_IN);

        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(exitRecipient);

        assertEq(amount, 2 * AVAX_IN, "returned amount");
        assertEq(exitRecipient.balance, 2 * AVAX_IN, "recipient receives every AVAX");
        assertEq(address(paymentRails).balance, 0, "rails must be drained");
    }

    function test_WhenTheOwnerSweepsToAContract() external {
        _sendAvax(AVAX_IN);
        uint256 before = address(coordinator).balance;

        vm.prank(owner);
        paymentRails.sweepNative(address(coordinator));

        assertEq(address(coordinator).balance - before, AVAX_IN);
    }

    function test_RevertWhen_ANonOwnerSweeps() external {
        _sendAvax(AVAX_IN);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, keeper));
        vm.prank(keeper);
        paymentRails.sweepNative(keeper);

        assertEq(address(paymentRails).balance, AVAX_IN, "nothing may move");
    }

    function test_RevertWhen_TheOwnerSweepsWithNothingHeld() external {
        vm.expectRevert(Errors.PaymentRails_ZeroNativeBalance.selector);
        vm.prank(owner);
        paymentRails.sweepNative(owner);
    }

    function test_WhenNativeAndAWavaxRouteCoexist() external {
        DexSwapModule module = new DexSwapModule(SWAP_ROUTER_02, address(0), 0);
        // Params are built before the prank: encodeParams is an external call and would consume it.
        bytes memory params = _wavaxToUsdcParams(module);
        vm.prank(owner);
        paymentRails.configureToken(WAVAX, "SWAP", address(module), 0, params, true);

        // WAVAX arrives as a token (minted through the real contract), AVAX arrives as native.
        vm.startPrank(sender);
        IWAVAX(WAVAX).deposit{ value: AVAX_IN }();
        IERC20(WAVAX).transfer(address(paymentRails), AVAX_IN);
        vm.stopPrank();
        _sendAvax(AVAX_IN);

        vm.prank(keeper);
        bool success = paymentRails.executeAction(WAVAX, AVAX_IN);

        assertTrue(success, "WAVAX route must swap through the real SwapRouter02");
        assertEq(IERC20(WAVAX).balanceOf(address(paymentRails)), 0, "WAVAX sold");
        uint256 usdcOut = IERC20(USDC).balanceOf(address(paymentRails));
        assertGt(usdcOut, 0, "USDC landed on the rails");
        assertEq(address(paymentRails).balance, AVAX_IN, "the swap must not touch native");

        vm.prank(owner);
        paymentRails.sweepNative(owner);

        assertEq(owner.balance, AVAX_IN, "sweep takes native only");
        assertEq(IERC20(USDC).balanceOf(address(paymentRails)), usdcOut, "sweep must not touch token balances");
    }

    function test_WhenCreatedByTheFactory() external {
        PaymentRailsFactory factory = new PaymentRailsFactory(address(this));
        bytes32 salt = keccak256("rain-avalanche");

        address predicted = factory.predictDeterministicAddress(owner, salt);
        PaymentRails instance = PaymentRails(payable(factory.createDeterministic(owner, salt)));
        assertEq(address(instance), predicted, "predicted address must match");

        coordinator.sendWithTransfer(payable(address(instance)), AVAX_IN);
        address exitRecipient = makeAddr("exitRecipient");
        vm.prank(owner);
        assertEq(instance.sweepNative(exitRecipient), AVAX_IN);
        assertEq(exitRecipient.balance, AVAX_IN);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _sendAvax(uint256 amount) internal {
        vm.prank(sender);
        (bool ok,) = address(paymentRails).call{ value: amount }("");
        assertTrue(ok, "AVAX send failed");
    }

    function _wavaxToUsdcParams(DexSwapModule module) internal pure returns (bytes memory) {
        return module.encodeParams(
            DataTypes.DexSwapParams({
                targetToken: USDC,
                fee: FEE_LOW,
                maxSlippageBps: SLIPPAGE_BPS,
                sellTokenPriceFeed: AVAX_USD_FEED,
                buyTokenPriceFeed: USDC_USD_FEED,
                maxStaleness: ORACLE_MAX_STALENESS,
                swapDeadlineSeconds: DEFAULT_DEADLINE_SECONDS,
                maxAmount: 0
            })
        );
    }
}
