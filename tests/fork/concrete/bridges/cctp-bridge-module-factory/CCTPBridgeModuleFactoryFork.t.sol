// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { CCTPBridgeModule } from "../../../../../src/modules/bridges/CCTPBridgeModule.sol";
import { CCTPBridgeModuleFactory } from "../../../../../src/modules/bridges/CCTPBridgeModuleFactory.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title CCTPBridgeModuleFactoryFork_Test
/// @notice Fork tests proving the factory deploys working CCTPBridgeModules against Circle's real
/// TokenMessengerV2 and real USDC on Ethereum mainnet. The factory's claim is that every module it
/// lists burns the right token through the right messenger, so these tests burn real USDC through a
/// factory-deployed module — including the non-zero fee path, which is where a mis-wired module or a
/// mis-computed fee would actually cost money.
contract CCTPBridgeModuleFactoryFork_Test is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event CCTPBridgeModuleCreated(address indexed module, address indexed deployer);

    event BridgeInitiated(
        address indexed paymentRails,
        uint256 amount,
        uint32 indexed destinationDomain,
        bytes32 mintRecipient,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes hookData
    );

    /*//////////////////////////////////////////////////////////////////////////
                                MAINNET CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    address internal constant TOKEN_MESSENGER_V2 = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint32 internal constant DOMAIN_BASE = 6;
    uint32 internal constant DOMAIN_ARBITRUM = 3;
    uint256 internal constant BRIDGE_AMOUNT = 10_000e6;
    bytes32 internal constant DEFAULT_MINT_RECIPIENT =
        bytes32(uint256(uint160(0xBEeFbeefbEefbeEFbeEfbEEfBEeFbeEfBeEfBeef)));
    bytes32 internal constant NO_DESTINATION_CALLER = bytes32(0);

    uint32 internal constant FINALITY_STANDARD = 2000;
    uint32 internal constant FINALITY_FAST = 1000;

    /// @dev Non-zero fee: fast-finality transfers are the ones Circle actually charges for.
    uint16 internal constant FEE_BPS = 20; // 0.2%

    bytes32 internal constant DEFAULT_SALT = bytes32(uint256(1));

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    CCTPBridgeModuleFactory internal factory;
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

        vm.createSelectFork("ethereum", 22_300_000);

        owner = makeAddr("owner");
        deployer = makeAddr("deployer");

        factory = new CCTPBridgeModuleFactory(TOKEN_MESSENGER_V2, USDC);

        vm.prank(owner);
        paymentRails = new PaymentRails(owner);

        deal(USDC, address(paymentRails), BRIDGE_AMOUNT * 10);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _bridgeParams(
        address module,
        uint32 domain,
        uint16 maxFeeBps,
        uint32 finality,
        bytes memory hookData
    )
        internal
        pure
        returns (bytes memory)
    {
        return CCTPBridgeModule(module)
            .encodeParams(
                DataTypes.CCTPBridgeParams({
                    destinationDomain: domain,
                    mintRecipient: DEFAULT_MINT_RECIPIENT,
                    destinationCaller: NO_DESTINATION_CALLER,
                    maxFeeBps: maxFeeBps,
                    minFinalityThreshold: finality,
                    hookData: hookData
                })
            );
    }

    /*//////////////////////////////////////////////////////////////////////////
                    CONSTRUCTOR AGAINST THE REAL CCTP CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_Fork_FactoryDeploysAgainstRealCctpContracts() external view {
        assertEq(factory.tokenMessenger(), TOKEN_MESSENGER_V2);
        assertEq(factory.usdc(), USDC);
        assertTrue(TOKEN_MESSENGER_V2.code.length > 0);
        assertTrue(USDC.code.length > 0);
    }

    function test_Fork_RevertWhen_TokenMessengerIsEOA() external {
        address eoa = makeAddr("realChainEoa");
        vm.expectRevert(abi.encodeWithSelector(Errors.CCTPBridgeModuleFactory_TokenMessengerNotContract.selector, eoa));
        new CCTPBridgeModuleFactory(eoa, USDC);
    }

    function test_Fork_RevertWhen_UsdcIsEOA() external {
        address eoa = makeAddr("realChainEoaUsdc");
        vm.expectRevert(abi.encodeWithSelector(Errors.CCTPBridgeModuleFactory_USDCNotContract.selector, eoa));
        new CCTPBridgeModuleFactory(TOKEN_MESSENGER_V2, eoa);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        CREATE AGAINST THE REAL CCTP CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_Fork_Create_WiresRealCctpContracts() external {
        vm.prank(deployer);
        address module = factory.create();

        assertEq(CCTPBridgeModule(module).tokenMessenger(), TOKEN_MESSENGER_V2);
        assertEq(CCTPBridgeModule(module).usdc(), USDC);
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
        assertEq(CCTPBridgeModule(module).usdc(), USDC);
    }

    /*//////////////////////////////////////////////////////////////////////////
            END-TO-END: REAL USDC BURN VIA A FACTORY MODULE (ZERO FEE)
    //////////////////////////////////////////////////////////////////////////*/

    function test_Fork_FactoryModule_BridgesRealUsdcViaPaymentRails() external {
        vm.prank(deployer);
        address module = factory.create();

        bytes memory params = _bridgeParams(module, DOMAIN_BASE, 0, FINALITY_STANDARD, bytes(""));

        vm.prank(owner);
        paymentRails.configureToken(USDC, "CCTP_BRIDGE", module, BRIDGE_AMOUNT, params, true);

        uint256 railsBefore = IERC20(USDC).balanceOf(address(paymentRails));

        assertTrue(paymentRails.executeAction(USDC, BRIDGE_AMOUNT), "burn should succeed on real TokenMessengerV2");

        assertEq(IERC20(USDC).balanceOf(address(paymentRails)), railsBefore - BRIDGE_AMOUNT);
        // The module burns through and holds nothing, and leaves no standing messenger approval.
        assertEq(IERC20(USDC).balanceOf(module), 0);
        assertEq(IERC20(USDC).allowance(module, TOKEN_MESSENGER_V2), 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
        END-TO-END: REAL USDC BURN VIA A FACTORY MODULE (NON-ZERO FEE PATH)
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev The fee is computed from `maxFeeBps` and handed to the real TokenMessengerV2, which
    /// validates it. A zero-fee test would never exercise that validation, so this is the path that
    /// actually proves a factory-deployed module is correctly wired for paid transfers.
    function test_Fork_FactoryModule_BridgesWithNonZeroFee_ViaPaymentRails() external {
        vm.prank(deployer);
        address module = factory.create();

        bytes memory params = _bridgeParams(module, DOMAIN_BASE, FEE_BPS, FINALITY_FAST, bytes(""));
        uint256 expectedFee = (BRIDGE_AMOUNT * uint256(FEE_BPS)) / 10_000;
        assertGt(expectedFee, 0, "fee path must be exercised with a non-zero fee");

        vm.prank(owner);
        paymentRails.configureToken(USDC, "CCTP_BRIDGE", module, BRIDGE_AMOUNT, params, true);

        vm.expectEmit(true, true, true, true, module);
        emit BridgeInitiated(
            address(paymentRails), BRIDGE_AMOUNT, DOMAIN_BASE, DEFAULT_MINT_RECIPIENT, expectedFee, FINALITY_FAST, ""
        );

        assertTrue(
            paymentRails.executeAction(USDC, BRIDGE_AMOUNT), "non-zero fee burn should succeed on real TokenMessengerV2"
        );

        assertEq(IERC20(USDC).balanceOf(module), 0);
        assertEq(IERC20(USDC).allowance(module, TOKEN_MESSENGER_V2), 0);
    }

    /// @dev The estimate and the real burn must agree on the fee, or an integrator sizing a transfer
    /// off the estimate would be wrong by exactly the fee.
    function test_Fork_FactoryModule_NonZeroFee_EstimateMatchesAmountOut() external {
        vm.prank(deployer);
        address module = factory.create();

        bytes memory params = _bridgeParams(module, DOMAIN_BASE, FEE_BPS, FINALITY_FAST, bytes(""));
        uint256 expectedFee = (BRIDGE_AMOUNT * uint256(FEE_BPS)) / 10_000;

        // estimateOutput validates against msg.sender's balance, so ask it as the PaymentRails would.
        vm.prank(address(paymentRails));
        (uint256 estimated, address outputToken) = CCTPBridgeModule(module).estimateOutput(USDC, BRIDGE_AMOUNT, params);
        assertEq(outputToken, USDC);
        assertEq(estimated, BRIDGE_AMOUNT - expectedFee);

        vm.prank(address(paymentRails));
        IERC20(USDC).approve(module, BRIDGE_AMOUNT);

        vm.prank(address(paymentRails));
        DataTypes.ExecutionResult memory result = CCTPBridgeModule(module).execute(USDC, BRIDGE_AMOUNT, params);

        assertTrue(result.success);
        assertEq(result.amountOut, estimated, "estimate must match what the real burn reports");
    }

    /// @dev previewExecution sizes the transfer off the whole PaymentRails balance, so the fee it
    /// nets out must scale with that balance rather than with any per-call amount.
    function test_Fork_FactoryModule_NonZeroFee_PreviewNetsFeeOffFullBalance() external {
        vm.prank(deployer);
        address module = factory.create();

        bytes memory params = _bridgeParams(module, DOMAIN_BASE, FEE_BPS, FINALITY_FAST, bytes(""));

        vm.prank(owner);
        paymentRails.configureToken(USDC, "CCTP_BRIDGE", module, BRIDGE_AMOUNT, params, true);

        uint256 balance = IERC20(USDC).balanceOf(address(paymentRails));
        uint256 expectedFee = (balance * uint256(FEE_BPS)) / 10_000;

        (uint256 previewed, address outputToken) = paymentRails.previewExecution(USDC);

        assertEq(outputToken, USDC);
        assertEq(previewed, balance - expectedFee);
    }

    function test_Fork_FactoryModule_NonZeroFee_WithHookData_Succeeds() external {
        vm.prank(deployer);
        address module = factory.create();

        bytes memory params = _bridgeParams(module, DOMAIN_ARBITRUM, FEE_BPS, FINALITY_FAST, hex"deadbeef");

        vm.prank(owner);
        paymentRails.configureToken(USDC, "CCTP_BRIDGE", module, BRIDGE_AMOUNT, params, true);

        assertTrue(
            paymentRails.executeAction(USDC, BRIDGE_AMOUNT),
            "depositForBurnWithHook should succeed on real TokenMessengerV2"
        );
        assertEq(IERC20(USDC).balanceOf(module), 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            NON-USDC IS STILL REJECTED
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev The factory pins USDC, so a factory-deployed module must refuse any other real token
    /// rather than attempt a burn with it.
    function test_Fork_FactoryModule_RejectsRealNonUsdcToken() external {
        vm.prank(deployer);
        address module = factory.create();

        bytes memory params = _bridgeParams(module, DOMAIN_BASE, 0, FINALITY_STANDARD, bytes(""));

        (bool isValid,) = CCTPBridgeModule(module).validate(WETH, 1 ether, params);
        assertFalse(isValid, "a module wired to USDC must reject WETH");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        SHARED ACROSS TWO PAYMENT RAILS
    //////////////////////////////////////////////////////////////////////////*/

    function test_Fork_FactoryModule_SharedAcrossTwoPaymentRails() external {
        vm.prank(deployer);
        address module = factory.create();

        address secondOwner = makeAddr("secondOwner");
        vm.prank(secondOwner);
        PaymentRails secondRails = new PaymentRails(secondOwner);
        deal(USDC, address(secondRails), BRIDGE_AMOUNT);

        bytes memory params = _bridgeParams(module, DOMAIN_BASE, FEE_BPS, FINALITY_FAST, bytes(""));

        vm.prank(owner);
        paymentRails.configureToken(USDC, "CCTP_BRIDGE", module, BRIDGE_AMOUNT, params, true);

        vm.prank(secondOwner);
        secondRails.configureToken(USDC, "CCTP_BRIDGE", module, BRIDGE_AMOUNT, params, true);

        assertTrue(paymentRails.executeAction(USDC, BRIDGE_AMOUNT));
        assertTrue(secondRails.executeAction(USDC, BRIDGE_AMOUNT));

        assertEq(IERC20(USDC).balanceOf(module), 0);
    }
}
