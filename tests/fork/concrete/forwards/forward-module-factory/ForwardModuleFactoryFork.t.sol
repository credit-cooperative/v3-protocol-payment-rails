// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { ForwardModule } from "../../../../../src/modules/forwards/ForwardModule.sol";
import { ForwardModuleFactory } from "../../../../../src/modules/forwards/ForwardModuleFactory.sol";
import { PaymentRails } from "../../../../../src/core/PaymentRails.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ForwardModuleFactoryFork_Test
/// @notice Fork tests proving the factory deploys working ForwardModules on Ethereum mainnet —
/// provenance of the registry, CREATE2 prediction, and real USDC/WETH forwarded end-to-end through
/// PaymentRails by a factory-deployed module rather than a hand-constructed one.
contract ForwardModuleFactoryFork_Test is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event ForwardModuleCreated(address indexed module, address indexed deployer);

    /*//////////////////////////////////////////////////////////////////////////
                                MAINNET CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant USDC_AMOUNT = 10_000e6;
    uint256 internal constant WETH_AMOUNT = 5 ether;
    bytes32 internal constant DEFAULT_SALT = bytes32(uint256(1));

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    ForwardModuleFactory internal factory;
    PaymentRails internal paymentRails;

    address internal owner;
    address internal deployer;
    address internal recipient;

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
        recipient = makeAddr("recipient");

        factory = new ForwardModuleFactory();

        vm.prank(owner);
        paymentRails = new PaymentRails(owner);

        deal(USDC, address(paymentRails), USDC_AMOUNT * 10);
        deal(WETH, address(paymentRails), WETH_AMOUNT * 10);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _forwardParams(address module, uint256 minAmount) internal view returns (bytes memory) {
        return
            ForwardModule(module).encodeParams(DataTypes.ForwardParams({ recipient: recipient, minAmount: minAmount }));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    CREATE
    //////////////////////////////////////////////////////////////////////////*/

    function test_Fork_Create_DeploysWorkingModule() external {
        vm.prank(deployer);
        address module = factory.create();

        assertTrue(module.code.length > 0);
        assertEq(ForwardModule(module).moduleType(), "FORWARD");
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
        assertEq(ForwardModule(module).moduleType(), "FORWARD");
    }

    /*//////////////////////////////////////////////////////////////////////////
                    END-TO-END: REAL TOKENS VIA A FACTORY MODULE
    //////////////////////////////////////////////////////////////////////////*/

    function test_Fork_FactoryModule_ForwardsRealUsdcViaPaymentRails() external {
        vm.prank(deployer);
        address module = factory.create();

        // Build params before the prank: encodeParams is an external call that would consume it.
        bytes memory params = _forwardParams(module, 0);

        vm.prank(owner);
        paymentRails.configureToken(USDC, "FORWARD", module, USDC_AMOUNT, params, true);

        uint256 railsBefore = IERC20(USDC).balanceOf(address(paymentRails));

        assertTrue(paymentRails.executeAction(USDC, USDC_AMOUNT), "executeAction should succeed");

        assertEq(IERC20(USDC).balanceOf(recipient), USDC_AMOUNT);
        assertEq(IERC20(USDC).balanceOf(address(paymentRails)), railsBefore - USDC_AMOUNT);
        // The module is a pure conduit — it must never retain real tokens.
        assertEq(IERC20(USDC).balanceOf(module), 0);
    }

    /// @dev WETH as well as USDC: a factory-deployed module must handle any standard ERC20, not just
    /// the token the first test happened to use.
    function test_Fork_FactoryModule_ForwardsRealWethViaPaymentRails() external {
        vm.prank(deployer);
        address module = factory.create();

        bytes memory params = _forwardParams(module, 0);

        vm.prank(owner);
        paymentRails.configureToken(WETH, "FORWARD", module, WETH_AMOUNT, params, true);

        assertTrue(paymentRails.executeAction(WETH, WETH_AMOUNT), "executeAction should succeed");

        assertEq(IERC20(WETH).balanceOf(recipient), WETH_AMOUNT);
        assertEq(IERC20(WETH).balanceOf(module), 0);
    }

    /// @dev ForwardModule is stateless, so the deployment model the factory encourages is one shared
    /// module across instances. Proven here against real tokens rather than asserted in NatSpec.
    function test_Fork_FactoryModule_SharedAcrossTwoPaymentRails() external {
        vm.prank(deployer);
        address module = factory.create();

        address secondOwner = makeAddr("secondOwner");
        vm.prank(secondOwner);
        PaymentRails secondRails = new PaymentRails(secondOwner);
        deal(USDC, address(secondRails), USDC_AMOUNT);

        bytes memory params = _forwardParams(module, 0);

        vm.prank(owner);
        paymentRails.configureToken(USDC, "FORWARD", module, USDC_AMOUNT, params, true);

        address secondRecipient = makeAddr("secondRecipient");
        bytes memory secondParams =
            ForwardModule(module).encodeParams(DataTypes.ForwardParams({ recipient: secondRecipient, minAmount: 0 }));
        vm.prank(secondOwner);
        secondRails.configureToken(USDC, "FORWARD", module, USDC_AMOUNT, secondParams, true);

        assertTrue(paymentRails.executeAction(USDC, USDC_AMOUNT));
        assertTrue(secondRails.executeAction(USDC, USDC_AMOUNT));

        assertEq(IERC20(USDC).balanceOf(recipient), USDC_AMOUNT);
        assertEq(IERC20(USDC).balanceOf(secondRecipient), USDC_AMOUNT);
        assertEq(IERC20(USDC).balanceOf(module), 0);
    }
}
