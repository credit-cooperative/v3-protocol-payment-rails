// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, console2 } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PaymentRails } from "../../../../src/core/PaymentRails.sol";
import { PaymentRailsFactory } from "../../../../src/core/PaymentRailsFactory.sol";
import { DexSwapModule } from "../../../../src/modules/swaps/DexSwapModule.sol";
import { WrapModule } from "../../../../src/modules/native/WrapModule.sol";
import { UnwrapModule } from "../../../../src/modules/native/UnwrapModule.sol";
import { NativeForwardModule } from "../../../../src/modules/native/NativeForwardModule.sol";
import { DataTypes } from "../../../../src/types/DataTypes.sol";
import { Constants } from "../../../../src/libraries/Constants.sol";
import { StipendSender } from "../../../shared/mocks/NativeMocks.sol";

/// @notice Avalanche C-Chain fork tests for native routes on PaymentRails.
/// @dev Tree: tests/fork/concrete/native/paymentRailsNativeRoutesAvalancheFork.tree
///
/// Raw AVAX in, wrap and unwrap through the real WAVAX contract, swap through the real SwapRouter02
/// with live Chainlink feeds, and raw AVAX out. `vm.deal` only funds the senders.
contract PaymentRailsNativeRoutesAvalancheForkTest is Test {
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

    address internal constant NATIVE = Constants.NATIVE_TOKEN;
    uint256 internal constant AVAX_IN = 1 ether;

    event NativeReceived(address indexed sender, uint256 amount);
    event NativeReturned(address indexed sourceToken, address indexed module, uint256 amount);

    PaymentRails internal rails;
    DexSwapModule internal dex;
    WrapModule internal wrap;
    UnwrapModule internal unwrap;
    NativeForwardModule internal nativeForward;
    StipendSender internal coordinator;

    address internal owner;
    address internal keeper;
    address internal sender;

    function setUp() public {
        string memory rpcUrl = vm.envOr("AVALANCHE_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork("avalanche");

        owner = makeAddr("owner");
        keeper = makeAddr("keeper");
        sender = makeAddr("sender");

        rails = new PaymentRails(owner);
        dex = new DexSwapModule(SWAP_ROUTER_02, address(0), 0);
        wrap = new WrapModule(WAVAX);
        unwrap = new UnwrapModule(WAVAX);
        nativeForward = new NativeForwardModule();
        coordinator = new StipendSender();

        vm.deal(sender, 100 ether);
        vm.deal(address(coordinator), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_WhenAvaxIsSentWithCall() external {
        vm.expectEmit(true, false, false, true, address(rails));
        emit NativeReceived(sender, AVAX_IN);

        _sendAvax(AVAX_IN);

        assertEq(address(rails).balance, AVAX_IN);
    }

    function test_WhenAvaxIsSentWithTransfer() external {
        // transfer() forwards only the 2300-gas stipend
        coordinator.sendWithTransfer(payable(address(rails)), AVAX_IN);

        assertEq(address(rails).balance, AVAX_IN);
    }

    function test_GivenNativeRoutedToWrap() external {
        _routeNativeToWrap();
        _sendAvax(AVAX_IN);
        uint256 wavaxNativeBefore = WAVAX.balance;

        (uint256 estimated, address outputToken) = rails.previewExecution(NATIVE);
        assertEq(estimated, AVAX_IN, "preview amount");
        assertEq(outputToken, WAVAX, "preview output token");

        vm.prank(keeper);
        assertTrue(rails.executeAction(NATIVE, AVAX_IN), "wrap route must succeed");

        assertEq(IERC20(WAVAX).balanceOf(address(rails)), AVAX_IN, "real WAVAX minted 1:1");
        assertEq(address(rails).balance, 0, "native fully converted");
        assertEq(WAVAX.balance - wavaxNativeBefore, AVAX_IN, "WAVAX contract holds the AVAX");
        assertEq(address(wrap).balance, 0, "module native");
        assertEq(IERC20(WAVAX).balanceOf(address(wrap)), 0, "module WAVAX");
    }

    function test_GivenNativeRoutedToWrap_WhenWavaxIsRoutedToSwap() external {
        _routeNativeToWrap();
        bytes memory params = _wavaxToUsdcParams();
        vm.prank(owner);
        rails.configureToken(WAVAX, "SWAP", address(dex), 0, params, true);
        _sendAvax(AVAX_IN);

        vm.prank(keeper);
        rails.executeAction(NATIVE, AVAX_IN);

        (uint256 estimate,) = dex.estimateOutput(WAVAX, AVAX_IN, params);
        uint256 usdcBefore = IERC20(USDC).balanceOf(address(rails));

        vm.prank(keeper);
        bool success = rails.executeAction(WAVAX, AVAX_IN);

        uint256 received = IERC20(USDC).balanceOf(address(rails)) - usdcBefore;
        console2.log("native AVAX -> WRAP -> SWAP -> USDC received:", received, "oracle estimate:", estimate);

        assertTrue(success, "swap must succeed against the real router");
        assertGe(received, estimate * (10_000 - SLIPPAGE_BPS) / 10_000, "output below oracle floor");
        assertLe(received, estimate * (10_000 + SLIPPAGE_BPS) / 10_000, "output implausibly above estimate");
        assertEq(IERC20(WAVAX).balanceOf(address(dex)), 0, "swap module retained WAVAX");
    }

    function test_GivenNativeRoutedToNativeForward_WhenTheRecipientIsAnEOA() external {
        address recipient = makeAddr("recipient");
        _routeNativeToForward(recipient);
        _sendAvax(AVAX_IN);

        vm.prank(keeper);
        assertTrue(rails.executeAction(NATIVE, AVAX_IN));

        assertEq(recipient.balance, AVAX_IN, "recipient must receive raw AVAX");
        assertEq(address(rails).balance, 0);
        assertEq(address(nativeForward).balance, 0, "module native");
    }

    function test_GivenNativeRoutedToNativeForward_WhenTheRecipientIsAContract() external {
        _routeNativeToForward(address(coordinator));
        _sendAvax(AVAX_IN);
        uint256 before = address(coordinator).balance;

        vm.prank(keeper);
        assertTrue(rails.executeAction(NATIVE, AVAX_IN));

        assertEq(address(coordinator).balance - before, AVAX_IN);
    }

    function test_GivenWavaxRoutedToUnwrap() external {
        // Put real WAVAX on the rails through the wrap route, then flip the WAVAX route to UNWRAP.
        _routeNativeToWrap();
        _sendAvax(AVAX_IN);
        vm.prank(keeper);
        rails.executeAction(NATIVE, AVAX_IN);
        vm.prank(owner);
        rails.configureToken(WAVAX, "UNWRAP", address(unwrap), 0, "", true);

        vm.expectEmit(true, true, false, true, address(rails));
        emit NativeReturned(WAVAX, address(unwrap), AVAX_IN);
        vm.prank(keeper);
        assertTrue(rails.executeAction(WAVAX, AVAX_IN), "unwrap route must succeed");

        assertEq(address(rails).balance, AVAX_IN, "AVAX back on the rails");
        assertEq(IERC20(WAVAX).balanceOf(address(rails)), 0, "WAVAX burned");
        assertEq(address(unwrap).balance, 0, "module native");
        assertEq(IERC20(WAVAX).balanceOf(address(unwrap)), 0, "module WAVAX");
    }

    function test_GivenAvaxWasForceFedToAFreshRails() external {
        PaymentRails fresh = new PaymentRails(owner);
        // vm.deal models value that arrives without running receive()
        vm.deal(address(fresh), AVAX_IN);
        address exit = makeAddr("exit");
        bytes memory params = nativeForward.encodeParams(DataTypes.ForwardParams({ recipient: exit, minAmount: 0 }));
        vm.prank(owner);
        fresh.configureToken(NATIVE, "NATIVE_FORWARD", address(nativeForward), 0, params, true);

        vm.prank(keeper);
        assertTrue(fresh.executeAction(NATIVE, AVAX_IN));

        assertEq(exit.balance, AVAX_IN, "force-fed AVAX recovered");
    }

    function test_WhenCreatedByTheUnchangedFactory() external {
        PaymentRailsFactory factory = new PaymentRailsFactory(address(this));
        PaymentRails instance = PaymentRails(payable(factory.create(owner)));
        vm.prank(owner);
        instance.configureToken(NATIVE, "WRAP", address(wrap), 0, "", true);

        vm.prank(sender);
        (bool ok,) = address(instance).call{ value: AVAX_IN }("");
        assertTrue(ok);
        vm.prank(keeper);
        assertTrue(instance.executeAction(NATIVE, AVAX_IN));

        assertEq(IERC20(WAVAX).balanceOf(address(instance)), AVAX_IN);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _sendAvax(uint256 amount) internal {
        vm.prank(sender);
        (bool ok,) = address(rails).call{ value: amount }("");
        assertTrue(ok, "AVAX send failed");
    }

    function _routeNativeToWrap() internal {
        vm.prank(owner);
        rails.configureToken(NATIVE, "WRAP", address(wrap), 0, "", true);
    }

    function _routeNativeToForward(address to) internal {
        bytes memory params = nativeForward.encodeParams(DataTypes.ForwardParams({ recipient: to, minAmount: 0 }));
        vm.prank(owner);
        rails.configureToken(NATIVE, "NATIVE_FORWARD", address(nativeForward), 0, params, true);
    }

    function _wavaxToUsdcParams() internal view returns (bytes memory) {
        return dex.encodeParams(
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
