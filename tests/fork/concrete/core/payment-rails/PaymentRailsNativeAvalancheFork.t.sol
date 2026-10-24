// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm, console2 } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { PaymentRailsFactory } from "../../../../../src/core/PaymentRailsFactory.sol";
import { DexSwapModule } from "../../../../../src/modules/swaps/DexSwapModule.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { StipendSender } from "../../../../shared/mocks/NativeMocks.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Avalanche C-Chain fork tests for native AVAX ingress on PaymentRails.
/// @dev Tree: tests/fork/concrete/core/payment-rails/paymentRailsNativeAvalancheFork.tree
///
/// Raw AVAX in, wrap through the real WAVAX contract, swap through the real SwapRouter02 with live
/// Chainlink feeds. `vm.deal` only funds the senders.
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
    event NativeWrapped(address indexed caller, uint256 amount);
    event NativeSwept(address indexed recipient, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    PaymentRails internal paymentRails;
    DexSwapModule internal module;
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

        module = new DexSwapModule(SWAP_ROUTER_02, address(0), 0);
        paymentRails = new PaymentRails(owner, WAVAX);
        coordinator = new StipendSender();

        vm.deal(sender, 100 ether);
        vm.deal(address(coordinator), 100 ether);

        // Params are built before the prank: encodeParams is an external call and would consume it.
        bytes memory params = _wavaxToUsdcParams();
        vm.prank(owner);
        paymentRails.configureToken(WAVAX, "SWAP", address(module), 0, params, true);
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

    function test_WhenWrapNativeIsCalled() external {
        _sendAvax(AVAX_IN);
        uint256 wavaxContractNativeBefore = WAVAX.balance;

        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit NativeWrapped(keeper, AVAX_IN);

        vm.prank(keeper);
        uint256 wrapped = paymentRails.wrapNative();

        assertEq(wrapped, AVAX_IN);
        assertEq(IERC20(WAVAX).balanceOf(address(paymentRails)), AVAX_IN, "WAVAX not credited 1:1");
        assertEq(address(paymentRails).balance, 0, "native balance must be fully swept");
        assertEq(WAVAX.balance - wavaxContractNativeBefore, AVAX_IN, "WAVAX contract did not receive the AVAX");
    }

    function test_WhenTheWrappedBalanceIsExecuted() external {
        _sendAvax(AVAX_IN);
        vm.prank(keeper);
        paymentRails.wrapNative();

        bytes memory params = _wavaxToUsdcParams();
        (uint256 estimate,) = module.estimateOutput(WAVAX, AVAX_IN, params);
        uint256 usdcBefore = IERC20(USDC).balanceOf(address(paymentRails));

        vm.prank(keeper);
        bool success = paymentRails.executeAction(WAVAX, AVAX_IN);

        uint256 received = IERC20(USDC).balanceOf(address(paymentRails)) - usdcBefore;
        console2.log("native AVAX -> WAVAX -> USDC received:", received, "oracle estimate:", estimate);

        assertTrue(success, "swap must succeed against the real router");
        assertEq(IERC20(WAVAX).balanceOf(address(paymentRails)), 0, "WAVAX not fully spent");
        assertGe(received, estimate * (10_000 - SLIPPAGE_BPS) / 10_000, "output below oracle floor");
        assertLe(received, estimate * (10_000 + SLIPPAGE_BPS) / 10_000, "output implausibly above estimate");
        assertEq(IERC20(WAVAX).balanceOf(address(module)), 0, "module retained WAVAX");
        assertEq(IERC20(USDC).balanceOf(address(module)), 0, "module retained USDC");
        assertEq(IERC20(WAVAX).allowance(address(module), SWAP_ROUTER_02), 0, "router allowance not revoked");
    }

    function test_RevertWhen_WrapNativeIsCalledWithNothingToWrap() external {
        vm.expectRevert(Errors.PaymentRails_ZeroNativeBalance.selector);
        paymentRails.wrapNative();
    }

    function test_WhenTheOwnerSweepsRawAvax() external {
        _sendAvax(AVAX_IN);
        address exitRecipient = makeAddr("exitRecipient");

        vm.expectEmit(true, false, false, true, address(paymentRails));
        emit NativeSwept(exitRecipient, AVAX_IN);

        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(exitRecipient);

        assertEq(amount, AVAX_IN);
        assertEq(exitRecipient.balance, AVAX_IN, "recipient must receive the whole native balance");
        assertEq(address(paymentRails).balance, 0, "rails must be drained");
    }

    function test_WhenTheOwnerSweepsWithRealWavaxOnTheRails() external {
        _sendAvax(AVAX_IN);
        vm.prank(keeper);
        paymentRails.wrapNative();
        _sendAvax(AVAX_IN);
        address exitRecipient = makeAddr("exitRecipient");
        uint256 wavaxContractNativeBefore = WAVAX.balance;

        vm.recordLogs();
        vm.prank(owner);
        uint256 amount = paymentRails.sweepNative(exitRecipient);

        bytes32 receivedSig = keccak256("NativeReceived(address,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(paymentRails)) {
                assertTrue(logs[i].topics[0] != receivedSig, "the WAVAX payout must not be logged as a receipt");
            }
        }

        assertEq(amount, 2 * AVAX_IN, "native plus unwrapped");
        assertEq(exitRecipient.balance, 2 * AVAX_IN, "recipient receives native plus unwrapped");
        assertEq(IERC20(WAVAX).balanceOf(address(paymentRails)), 0, "real WAVAX burned");
        assertEq(wavaxContractNativeBefore - WAVAX.balance, AVAX_IN, "WAVAX contract paid out the AVAX");
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

    function test_GivenARailWithoutAWrapper() external {
        PaymentRails bare = new PaymentRails(owner, address(0));
        // vm.deal models value that arrives without running receive()
        vm.deal(address(bare), AVAX_IN);
        address exitRecipient = makeAddr("exitRecipient");

        vm.prank(owner);
        bare.sweepNative(exitRecipient);

        assertEq(exitRecipient.balance, AVAX_IN, "force-fed AVAX must be recoverable by the owner");
        assertEq(address(bare).balance, 0);
    }

    function test_WhenCreatedByAFactoryBuiltWithWavax() external {
        PaymentRailsFactory factory = new PaymentRailsFactory(address(this), WAVAX);
        bytes32 salt = keccak256("rain-avalanche");

        address predicted = factory.predictDeterministicAddress(owner, salt);
        PaymentRails instance = PaymentRails(payable(factory.createDeterministic(owner, salt)));

        assertEq(address(instance), predicted, "init code hash must cover both constructor args");
        assertEq(instance.wrappedNative(), WAVAX);

        vm.prank(sender);
        (bool ok,) = address(instance).call{ value: AVAX_IN }("");
        assertTrue(ok);
        vm.prank(keeper);
        assertEq(instance.wrapNative(), AVAX_IN);
        assertEq(IERC20(WAVAX).balanceOf(address(instance)), AVAX_IN);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _sendAvax(uint256 amount) internal {
        vm.prank(sender);
        (bool ok,) = address(paymentRails).call{ value: amount }("");
        assertTrue(ok, "AVAX send failed");
    }

    function _wavaxToUsdcParams() internal view returns (bytes memory) {
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
