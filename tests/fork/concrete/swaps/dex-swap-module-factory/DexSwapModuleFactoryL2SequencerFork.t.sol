// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { DexSwapModule } from "../../../../../src/modules/swaps/DexSwapModule.sol";
import { DexSwapModuleFactory } from "../../../../../src/modules/swaps/DexSwapModuleFactory.sol";
import { DataTypes } from "../../../../../src/types/DataTypes.sol";
import { Errors } from "../../../../../src/libraries/Errors.sol";

/// @title DexSwapModuleFactoryL2SequencerFork_Test
/// @notice Fork tests for the L2 profile of DexSwapModuleFactory, against Base mainnet.
/// @dev The Ethereum fork suite deploys with `sequencerUptimeFeed = address(0)`, which skips the
/// constructor's sequencer-feed check entirely. These tests run that check against Base's real
/// Chainlink L2 Sequencer Uptime Feed, so the guard is proven to accept production configuration
/// rather than only to reject an EOA in a unit test. They also read the live feed through a
/// factory-deployed module, so the wiring is shown to be usable, not merely stored.
///
///      Run with: forge test --match-contract DexSwapModuleFactoryL2SequencerFork -vvv
contract DexSwapModuleFactoryL2SequencerFork_Test is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                BASE MAINNET CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    address internal constant UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant SEQUENCER_UPTIME_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;

    address internal constant ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address internal constant USDC_USD_FEED = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;

    /// @dev At this block the sequencer feed reports up (answer 0) and last restarted ~80 days
    /// earlier, so a normal grace period is long past.
    uint256 internal constant FORK_BLOCK = 51_340_000;

    uint256 internal constant GRACE_PERIOD = 3600;
    uint256 internal constant ORACLE_MAX_STALENESS = 86_400;
    uint256 internal constant DEADLINE_SECONDS = 600;
    uint24 internal constant FEE_LOW = 500;
    uint16 internal constant SLIPPAGE_BPS = 200;

    uint256 internal constant WETH_SELL_AMOUNT = 1 ether;

    bytes32 internal constant DEFAULT_SALT = bytes32(uint256(1));

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    DexSwapModuleFactory internal factory;

    /*//////////////////////////////////////////////////////////////////////////
                                    SETUP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        string memory rpcUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
        }

        vm.createSelectFork("base", FORK_BLOCK);

        factory = new DexSwapModuleFactory(UNISWAP_V3_ROUTER, SEQUENCER_UPTIME_FEED, GRACE_PERIOD);

        // validate() measures the caller's balance, so fund this contract as the would-be PaymentRails.
        deal(WETH, address(this), WETH_SELL_AMOUNT * 10);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _swapParams() internal pure returns (bytes memory) {
        return abi.encode(
            DataTypes.DexSwapParams({
                targetToken: USDC,
                fee: FEE_LOW,
                maxSlippageBps: SLIPPAGE_BPS,
                sellTokenPriceFeed: ETH_USD_FEED,
                buyTokenPriceFeed: USDC_USD_FEED,
                maxStaleness: ORACLE_MAX_STALENESS,
                swapDeadlineSeconds: DEADLINE_SECONDS,
                maxAmount: 0
            })
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTRUCTOR GUARD
    //////////////////////////////////////////////////////////////////////////*/

    function test_WhenSequencerFeedIsTheRealChainlinkFeed_ShouldDeploy() external view {
        assertEq(factory.sequencerUptimeFeed(), SEQUENCER_UPTIME_FEED);
        assertEq(factory.sequencerGracePeriod(), GRACE_PERIOD);
        assertEq(factory.router(), UNISWAP_V3_ROUTER);
    }

    function test_RevertWhen_SequencerFeedIsEOA() external {
        address eoa = makeAddr("eoaSequencerFeed");
        vm.expectRevert(abi.encodeWithSelector(Errors.DexSwapModuleFactory_SequencerFeedNotContract.selector, eoa));
        new DexSwapModuleFactory(UNISWAP_V3_ROUTER, eoa, GRACE_PERIOD);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE WIRING
    //////////////////////////////////////////////////////////////////////////*/

    function test_WhenCreate_ShouldWireTheRealSequencerFeed() external {
        DexSwapModule module = DexSwapModule(factory.create());
        assertEq(module.sequencerUptimeFeed(), SEQUENCER_UPTIME_FEED);
        assertEq(module.sequencerGracePeriod(), GRACE_PERIOD);
    }

    function test_WhenCreateDeterministic_ShouldWireTheRealSequencerFeed() external {
        address predicted = factory.predictDeterministicAddress(DEFAULT_SALT);
        DexSwapModule module = DexSwapModule(factory.createDeterministic(DEFAULT_SALT));
        assertEq(address(module), predicted);
        assertEq(module.sequencerUptimeFeed(), SEQUENCER_UPTIME_FEED);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            LIVE SEQUENCER FEED READS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Proves the accepted feed is actually readable: validation walks the sequencer check
    /// against the live feed before it ever touches the price feeds.
    function test_WhenSequencerIsUp_ShouldValidateAgainstTheLiveFeed() external {
        DexSwapModule module = DexSwapModule(factory.create());

        (bool isValid, string memory reason) = module.validate(WETH, WETH_SELL_AMOUNT, _swapParams());

        assertTrue(isValid, reason);
        assertEq(reason, "");
    }

    /// @dev The mirror image: with a grace period longer than the feed's time since restart, the
    /// same live feed must block the swap. Without this, a feed that is merely present but never
    /// consulted would pass the test above.
    function test_WhenGracePeriodHasNotElapsed_ShouldRejectTheSwap() external {
        DexSwapModuleFactory strictFactory =
            new DexSwapModuleFactory(UNISWAP_V3_ROUTER, SEQUENCER_UPTIME_FEED, 365 days);
        DexSwapModule module = DexSwapModule(strictFactory.create());

        (bool isValid, string memory reason) = module.validate(WETH, WETH_SELL_AMOUNT, _swapParams());

        assertFalse(isValid);
        assertEq(reason, "Oracle price unavailable");
    }
}
