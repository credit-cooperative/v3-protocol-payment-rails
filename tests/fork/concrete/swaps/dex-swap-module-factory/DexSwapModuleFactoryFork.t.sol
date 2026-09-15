// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { DexSwapModule } from "../../../../../src/modules/swaps/DexSwapModule.sol";
import { DexSwapModuleFactory } from "../../../../../src/modules/swaps/DexSwapModuleFactory.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DexSwapModuleFactoryFork_Test
/// @notice Fork tests proving the factory deploys working DexSwapModules against the real Uniswap V3
/// SwapRouter and real Chainlink feeds on Ethereum mainnet. The factory's whole claim is that every
/// module it lists carries this chain's router, so these tests execute real swaps through a
/// factory-deployed module rather than only reading its immutables back.
contract DexSwapModuleFactoryFork_Test is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event DexSwapModuleCreated(address indexed module, address indexed deployer);

    event SwapExecuted(
        address indexed paymentRails, address indexed sellToken, address buyToken, uint256 amountIn, uint256 amountOut
    );

    /*//////////////////////////////////////////////////////////////////////////
                                MAINNET CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    address internal constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address internal constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    uint256 internal constant ORACLE_MAX_STALENESS = 86_400;
    uint256 internal constant DEFAULT_DEADLINE_SECONDS = 600;

    uint256 internal constant USDC_SELL_AMOUNT = 2000e6;
    uint256 internal constant WETH_SELL_AMOUNT = 1 ether;

    uint24 internal constant FEE_LOW = 500;
    uint24 internal constant FEE_MEDIUM = 3000;
    uint16 internal constant SLIPPAGE_BPS = 200; // 2%

    bytes32 internal constant DEFAULT_SALT = bytes32(uint256(1));

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    DexSwapModuleFactory internal factory;
    PaymentRails internal paymentRails;

    address internal owner;
    address internal deployer;

    /*//////////////////////////////////////////////////////////////////////////
                                    SETUP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        string memory rpcUrl = vm.envOr("ETHEREUM_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
        }

        vm.createSelectFork("ethereum", 21_900_000);

        owner = makeAddr("owner");
        deployer = makeAddr("deployer");

        // L1 profile: no sequencer uptime feed.
        factory = new DexSwapModuleFactory(UNISWAP_V3_ROUTER, address(0), 0);

        vm.prank(owner);
        paymentRails = new PaymentRails(owner);

        deal(USDC, address(paymentRails), USDC_SELL_AMOUNT * 10);
        deal(WETH, address(paymentRails), WETH_SELL_AMOUNT * 10);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _swapParams(
        address module,
        address targetToken,
        uint24 fee,
        address sellTokenPriceFeed,
        address buyTokenPriceFeed
    )
        internal
        pure
        returns (bytes memory)
    {
        return DexSwapModule(module)
            .encodeParams(
                DataTypes.DexSwapParams({
                    targetToken: targetToken,
                    fee: fee,
                    maxSlippageBps: SLIPPAGE_BPS,
                    sellTokenPriceFeed: sellTokenPriceFeed,
                    buyTokenPriceFeed: buyTokenPriceFeed,
                    maxStaleness: ORACLE_MAX_STALENESS,
                    swapDeadlineSeconds: DEFAULT_DEADLINE_SECONDS,
                    maxAmount: 0
                })
            );
    }

    /*//////////////////////////////////////////////////////////////////////////
                    CONSTRUCTOR AGAINST THE REAL ROUTER
    //////////////////////////////////////////////////////////////////////////*/

    function test_Fork_FactoryDeploysAgainstRealRouter() external view {
        assertEq(factory.router(), UNISWAP_V3_ROUTER);
        assertTrue(UNISWAP_V3_ROUTER.code.length > 0);
    }

    function test_Fork_RevertWhen_RouterIsEOA() external {
        address eoa = makeAddr("realChainEoa");
        vm.expectRevert(abi.encodeWithSelector(Errors.DexSwapModuleFactory_RouterNotContract.selector, eoa));
        new DexSwapModuleFactory(eoa, address(0), 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        CREATE AGAINST THE REAL ROUTER
    //////////////////////////////////////////////////////////////////////////*/

    function test_Fork_Create_WiresRealRouter() external {
        vm.prank(deployer);
        address module = factory.create();
        assertEq(DexSwapModule(module).router(), UNISWAP_V3_ROUTER);
    }

    function test_Fork_Create_RegistersModule() external {
        vm.prank(deployer);
        address module = factory.create();

        assertTrue(factory.isDeployedModule(module));
        assertEq(factory.getModuleCount(), 1);
        assertEq(factory.getDeployedModules()[0], module);
    }

    function test_Fork_CreateDeterministic_MatchesPrediction() external {
        address predicted = factory.predictDeterministicAddress(DEFAULT_SALT);

        vm.prank(deployer);
        address module = factory.createDeterministic(DEFAULT_SALT);

        assertEq(module, predicted);
        assertEq(DexSwapModule(module).router(), UNISWAP_V3_ROUTER);
    }

    /*//////////////////////////////////////////////////////////////////////////
                END-TO-END: REAL UNISWAP V3 SWAP VIA A FACTORY MODULE
    //////////////////////////////////////////////////////////////////////////*/

    function test_Fork_FactoryModule_SwapsRealUsdcForWethViaPaymentRails() external {
        vm.prank(deployer);
        address module = factory.create();

        bytes memory params = _swapParams(module, WETH, FEE_LOW, USDC_USD_FEED, ETH_USD_FEED);

        vm.prank(owner);
        paymentRails.configureToken(USDC, "SWAP", module, USDC_SELL_AMOUNT, params, true);

        uint256 wethBefore = IERC20(WETH).balanceOf(address(paymentRails));
        uint256 usdcBefore = IERC20(USDC).balanceOf(address(paymentRails));

        assertTrue(paymentRails.executeAction(USDC, USDC_SELL_AMOUNT), "swap should succeed on real router");

        assertEq(IERC20(USDC).balanceOf(address(paymentRails)), usdcBefore - USDC_SELL_AMOUNT);
        assertGt(IERC20(WETH).balanceOf(address(paymentRails)), wethBefore, "PaymentRails should receive real WETH");

        // The module stages nothing: no dust left behind and no standing router approval.
        assertEq(IERC20(USDC).balanceOf(module), 0);
        assertEq(IERC20(WETH).balanceOf(module), 0);
        assertEq(IERC20(USDC).allowance(module, UNISWAP_V3_ROUTER), 0);
    }

    function test_Fork_FactoryModule_SwapsRealWethForUsdcViaPaymentRails() external {
        vm.prank(deployer);
        address module = factory.create();

        bytes memory params = _swapParams(module, USDC, FEE_LOW, ETH_USD_FEED, USDC_USD_FEED);

        vm.prank(owner);
        paymentRails.configureToken(WETH, "SWAP", module, WETH_SELL_AMOUNT, params, true);

        uint256 usdcBefore = IERC20(USDC).balanceOf(address(paymentRails));

        assertTrue(paymentRails.executeAction(WETH, WETH_SELL_AMOUNT), "swap should succeed on real router");

        assertGt(IERC20(USDC).balanceOf(address(paymentRails)), usdcBefore);
        assertEq(IERC20(WETH).balanceOf(module), 0);
    }

    /// @dev The oracle floor is the module's only protection, and it is computed from the real
    /// Chainlink feeds at the fork block. A factory-deployed module must enforce it, so the swap is
    /// checked against a floor derived independently from `estimateOutput`.
    function test_Fork_FactoryModule_EnforcesRealOracleFloor() external {
        vm.prank(deployer);
        address module = factory.create();

        bytes memory params = _swapParams(module, WETH, FEE_LOW, USDC_USD_FEED, ETH_USD_FEED);

        vm.prank(address(paymentRails));
        (uint256 estimated, address outputToken) = DexSwapModule(module).estimateOutput(USDC, USDC_SELL_AMOUNT, params);
        assertEq(outputToken, WETH);
        assertGt(estimated, 0, "real Chainlink feeds should produce a non-zero estimate");

        uint256 floor = (estimated * (10_000 - SLIPPAGE_BPS)) / 10_000;

        vm.prank(owner);
        paymentRails.configureToken(USDC, "SWAP", module, USDC_SELL_AMOUNT, params, true);

        uint256 wethBefore = IERC20(WETH).balanceOf(address(paymentRails));
        assertTrue(paymentRails.executeAction(USDC, USDC_SELL_AMOUNT));
        uint256 received = IERC20(WETH).balanceOf(address(paymentRails)) - wethBefore;

        assertGe(received, floor, "real swap output must clear the oracle-derived floor");
    }

    /// @dev DexSwapModule is stateless, so the factory's deployment model is one shared module.
    /// Proven against the real router with two independently-owned PaymentRails.
    function test_Fork_FactoryModule_SharedAcrossTwoPaymentRails() external {
        vm.prank(deployer);
        address module = factory.create();

        address secondOwner = makeAddr("secondOwner");
        vm.prank(secondOwner);
        PaymentRails secondRails = new PaymentRails(secondOwner);
        deal(DAI, address(secondRails), 2000e18);

        bytes memory usdcParams = _swapParams(module, WETH, FEE_LOW, USDC_USD_FEED, ETH_USD_FEED);
        bytes memory daiParams = _swapParams(module, WETH, FEE_MEDIUM, DAI_USD_FEED, ETH_USD_FEED);

        vm.prank(owner);
        paymentRails.configureToken(USDC, "SWAP", module, USDC_SELL_AMOUNT, usdcParams, true);

        vm.prank(secondOwner);
        secondRails.configureToken(DAI, "SWAP", module, 2000e18, daiParams, true);

        assertTrue(paymentRails.executeAction(USDC, USDC_SELL_AMOUNT));
        assertTrue(secondRails.executeAction(DAI, 2000e18));

        assertGt(IERC20(WETH).balanceOf(address(paymentRails)), 0);
        assertGt(IERC20(WETH).balanceOf(address(secondRails)), 0);
        assertEq(IERC20(WETH).balanceOf(module), 0);
    }
}
