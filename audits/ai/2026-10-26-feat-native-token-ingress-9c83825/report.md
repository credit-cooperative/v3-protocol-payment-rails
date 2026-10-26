# 🔐 Security Review — v3-protocol-payment-rails

---

## Scope

|                                  |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mode**                         | default                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **Files reviewed**               | `./src/types/DataTypes.sol` · `./src/core/PaymentRailsFactory.sol` · `./src/core/PaymentRails.sol`<br>`./src/libraries/Errors.sol` · `./src/abstracts/ActionModuleBase.sol` · `./src/modules/swaps/CowSwapModuleFactory.sol`<br>`./src/modules/swaps/DexSwapModule.sol` · `./src/modules/swaps/CowSwapModule.sol` · `./src/modules/bridges/CCTPBridgeModule.sol`<br>`./src/modules/forwards/ForwardModule.sol` · `./src/modules/contrib/bridges/AtumModuleFactory.sol` · `./src/modules/contrib/bridges/AtumModule.sol`<br>`./scripts/solidity/Base.s.sol` · `./scripts/solidity/deploy/DeployCowSwapModuleFactory.s.sol` · `./scripts/solidity/deploy/DeployAtumModuleFactory.s.sol`<br>`./scripts/solidity/deploy/DeployDexSwapModule.s.sol` · `./scripts/solidity/deploy/DeployCowSwapModule.s.sol` · `./scripts/solidity/deploy/DeployForwardModule.s.sol`<br>`./scripts/solidity/deploy/DeployPaymentRailsFactory.s.sol` · `./scripts/solidity/deploy/DeployAtumModule.s.sol` · `./scripts/solidity/deploy/DeployPaymentRails.s.sol`<br>`./scripts/solidity/deploy/DeployCCTPBridgeModule.s.sol` · `./src/interfaces/IPaymentRails.sol` · `./src/interfaces/IPaymentRailsFactory.sol`<br>`./src/interfaces/IWETH9.sol` |
| **Confidence threshold (1-100)** | 75                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **Passes**                       | 3 (pass 1 ran 6/12 agents, pass 2 ran 7/12 agents, pass 3 ran 8/12 agents)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **Memory**                       | 12 records before this scan · 46 after · `3d88946`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

---

## Findings

[75] **1. AtumModuleFactory rejects every rail from a PR #23 factory**

`AtumModuleFactory.create` · Confidence: 75 · seen in 1/3 runs · NEW

**Description**
The owner cannot create an Atum module for a rail from the new PR #23 PaymentRailsFactory, because `_checkPaymentRailsDeployed` asks only the old immutable factory.

**Fix (Option A — redeploy)**

```diff
  // PR #23 rollout, per chain:
  // 1. deploy PaymentRailsFactory(owner, wrappedNative)
+ // 2. deploy AtumModuleFactory(owner, ..., newPaymentRailsFactory)
+ // 3. record both in deployments/<chainId>.json before creating rails
```

**Fix (Option B — trusted factory list)**

```diff
-    IPaymentRailsFactory public immutable paymentRailsFactory;
+    mapping(address factory => bool trusted) public isTrustedPaymentRailsFactory;
+
+    function setTrustedPaymentRailsFactory(address factory, bool trusted) external onlyOwner {
+        isTrustedPaymentRailsFactory[factory] = trusted;
+        emit TrustedPaymentRailsFactorySet(factory, trusted);
+    }
```

---

[75] **2. Any caller of DexSwapModule.execute takes the whole sell-token balance**

`DexSwapModule.execute` · Confidence: 75 · seen in 3/3 runs · NEW

**Description**
Any caller can call `execute` with 1 wei, and `_returnLeftover` sends the module's whole sell-token balance to that caller, because execute checks no caller.

**Fix**

```diff
-        (bool ok, uint256 amountOut) = _executeSwap(token, amount, cfg, oracleFloor);
-
-        _returnLeftover(token, msg.sender);
+        uint256 sellBefore = IERC20(token).balanceOf(address(this));
+        (bool ok, uint256 amountOut) = _executeSwap(token, amount, cfg, oracleFloor);
+
+        // Pay back only what this call left behind, never a balance that was already here.
+        uint256 leftover = IERC20(token).balanceOf(address(this)) - sellBefore;
+        if (leftover > 0) IERC20(token).safeTransfer(msg.sender, leftover);
```

---

[75] **3. Any caller can wrap native coin before the exit sweeps it**

`PaymentRails.wrapNative` · Confidence: 75 · seen in 1/3 runs · KNOWN (2 scans)

**Description**
Any caller can call `wrapNative` and then `executeAction(wrappedNative, …)` before the owner's `sweepNative`, so the configured route takes the value and the sweep reverts.

**Fix (Option A — restrict)**

```diff
-    function wrapNative() external nonReentrant {
+    function wrapNative() external onlyOwner nonReentrant {
```

**Fix (Option B — allow-and-handle)**

```diff
+    /// @dev Operational rule: disable the wrappedNative route with configureToken(wrappedNative, …, enabled=false)
+    ///      in the same multi-sig batch, before sweepNative. Otherwise any caller can wrap and route first.
     function sweepNative(address payable recipient) external onlyOwner nonReentrant {
```

---

Findings List

| #   | Confidence | Title                                                                  |
| --- | ---------- | ---------------------------------------------------------------------- |
| 1   | [75]       | AtumModuleFactory rejects every rail from a PR #23 factory             |
| 2   | [75]       | Any caller of DexSwapModule.execute takes the whole sell-token balance |
| 3   | [75]       | Any caller can wrap native coin before the exit sweeps it              |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **A 1-wei transfer blocks the next Atum route change** — `AtumModule.execute` · seen in 2/3 runs · NEW — Code smells: `_routeChangedWhileStaged` reads `balanceOf(this) > 0` as staged funds — An attacker who sends 1 wei after a route change makes execute fail until the keeper settles the 1 wei or the owner pauses and returns the balance. Re-confirmed present.
- **Permit2 pulls never lower pendingAmount** — `AtumModule.execute` · seen in 1/3 runs · NEW — Code smells: `pendingAmount[token] = available` stores the full balance and nothing lowers it on a pull — A keeper who reads pendingAmount sees more tokens than the module can send. We found no on-chain reader that acts on it.
- **Any caller can raise the Atum Permit2 allowance through executeAction** — `AtumModule.syncAllowance` · seen in 1/3 runs · NEW — Code smells: syncAllowance is onlyKeeper, but execute sets the allowance to the full module balance and any caller reaches execute — The onlyKeeper gate does not stop a caller who raises the allowance through executeAction. We did not prove that an unused signed digest exists then.
- **The CCTP fee cap rounds down and can fall one unit short** — `CCTPBridgeModule._validateBridgeParams` · seen in 3/3 runs · NEW — Code smells: `amount * maxFeeBps / 10_000` rounds down; with 1 bps every amount below 10_000 units gives a cap of 0 — A small transfer or a cap at the exact rate can fall short of the Circle minimum fee. We did not confirm how Circle rounds.
- **CCTP execute reports the fee cap as the bridge cost** — `CCTPBridgeModule.execute` · seen in 1/3 runs · NEW — Code smells: execute returns `amount - maxFee` as amountOut, not the fee Circle charges — The ActionExecuted amountOut can understate the minted USDC. We did not check whether an off-chain reader depends on it.
- **Any caller can call the CCTP bridge execute directly** — `CCTPBridgeModule.execute` · seen in 2/3 runs · NEW — Code smells: execute has no caller check — The module pulls only from the caller, so we found no path to another rail tokens.
- **validate accepts a CCTP fee cap that depositForBurn can reject** — `CCTPBridgeModule.validate` · seen in 1/3 runs · NEW — Code smells: `_validateBridgeParams` accepts any maxFeeBps below 10_000, including 0, with a fast finality threshold — validate reports success for a configuration that the Circle TokenMessengerV2 minimum fee can reject, so every executeAction emits ActionFailed. We did not confirm the Circle check on a fork.
- **CowSwapModuleFactory checks the rail less than AtumModuleFactory does** — `CowSwapModuleFactory._checkCreateParams` · seen in 2/3 runs · NEW — Code smells: only AtumModuleFactory checks the PaymentRailsFactory registry — Re-confirmed present; no outside attacker path.
- **A decimal gap of 78 or more makes validate panic** — `CowSwapModule._computeExpectedOutput` · seen in 1/3 runs · NEW — Code smells: `10 ** (buyExp - sellExp)` overflows at a gap of 78; DexSwapModule has the same code — A token or feed with absurd decimals makes validate revert with no reason. Only an owner configuration reaches this.
- **CowSwapModule accepts a slippage near 10_000 bps** — `CowSwapModule._validateSwapParams` · seen in 1/3 runs · NEW — Code smells: the same `> 10_000` bound accepts values that sign an order with buyAmount near zero — The owner can set a slippage near 10_000 bps, so a solver can fill the signed order for almost no buy token.
- **Expired CowSwap orders keep their tokens until the owner cancels each one** — `CowSwapModule.cancelOrder` · seen in 1/3 runs · NEW — Code smells: an expired order can never fill; cancelOrder is owner-only and takes one order; no batch cancel and no reclaim that any caller can run — Any caller can open many small orders, and the owner must cancel each expired order alone to get the tokens back. We did not prove that solvers leave the orders unfilled.
- **cancelOrder refunds from the balance that all pending orders share** — `CowSwapModule.cancelOrder` · seen in 2/3 runs · NEW — Code smells: `min(balanceOf(this), sellAmount)` reads a shared balance; no function returns tokens above the open-order total — One short order can take another order tokens, and a mistaken transfer to the module stays there forever. We found a shortfall path only for negative-rebase tokens.
- **A direct CowSwapModule deploy skips the factory sequencer checks** — `CowSwapModule.constructor` · seen in 2/3 runs · NEW — Code smells: the constructor checks none of the factory rules; DeployCowSwapModule.s.sol deploys directly — With grace 0, `_isSequencerHealthy` is always true after a restart. Re-confirmed present.
- **CowSwap orders use one maxStaleness value for two feeds** — `CowSwapModule.execute` · seen in 1/3 runs · NEW — Code smells: CowSwapParams has one `maxStaleness` for both feeds; the owner must set the slower heartbeat — A stopped fast feed still sets the order floor for the slow feed's whole window. We did not confirm such a stop on a production feed.
- **A solver can fill a CowSwap order at an old oracle floor** — `CowSwapModule.execute` · seen in 2/3 runs · NEW — Code smells: `buyAmount` is fixed at order creation and stays valid for `validityDuration`; any caller of executeAction picks when the order is made — A solver can fill the order at the old floor after the price goes up, so the rail receives less than the current value.
- **The oracle floor rounds down twice on small amounts** — `DexSwapModule._computeOracleFloor` · seen in 1/3 runs · NEW — Code smells: mulDiv in the expected output, then mulDiv by (10000 - bps); the same code is in CowSwapModule — Any caller who sends a tiny amount gets a floor that allows more loss than maxSlippageBps. The loss we found is one unit of the buy token.
- **The swap deadline uses the current block time** — `DexSwapModule._executeSwap` · seen in 1/3 runs · NEW — Code smells: `block.timestamp + swapDeadlineSeconds` is computed inside the executing transaction — The deadline never rejects a delayed transaction. The oracle floor is also computed live, so we found no loss.
- **A very large swapDeadlineSeconds passes validate and overflows in execute** — `DexSwapModule._executeSwap` · seen in 1/3 runs · NEW — Code smells: `_validateParams` rejects only zero; `block.timestamp + cfg.swapDeadlineSeconds` uses checked math — The owner can store a deadline that validate accepts, so previewExecution reports success and every executeAction fails with a panic.
- **A falling target balance makes the swap spend the input and report failure** — `DexSwapModule._executeSwap` · seen in 1/3 runs · NEW — Code smells: `if (buyTokenAfter < buyTokenBefore) return (false, 0);` runs after the router spent the input — For a rebasing target token, the swap spends the rail input and reports a failure, so the output stays in the module. We did not confirm that a configured target token reaches this branch.
- **One maxStaleness value covers two feeds with different heartbeats** — `DexSwapModule._getOraclePrice` · seen in 1/3 runs · NEW — Code smells: DexSwapParams has one `maxStaleness` for the sell feed and the buy feed; a 24h-heartbeat feed paired with a 1h feed forces a 24h bound — A stopped fast feed passes the check for up to the slow feed's heartbeat. We did not measure the price drift in that window.
- **DexSwapModule accepts maxSlippageBps of 10_000** — `DexSwapModule._validateParams` · seen in 1/3 runs · NEW — Code smells: `maxSlippageBps > 10_000` accepts 10_000, which gives a floor of 0; 9_999 gives a floor of expected/10_000 — At 10_000 every swap fails with a reason that blames the amount, and at 9_999 the oracle gate allows a 99.99% loss. Only the owner sets this value.
- **DexSwapModule accepts a sequencer feed with a zero grace period** — `DexSwapModule.constructor` · seen in 2/3 runs · NEW — Code smells: no check on `_sequencerUptimeFeed` or `_sequencerGracePeriod`; a feed address with no code makes the try/catch decode revert — A deployer who passes zero grace removes the restart delay, and a codeless feed makes every swap fail. Only a deployer can cause this.
- **The swap loss can exceed maxSlippageBps by the feed deviation threshold** — `DexSwapModule.execute` · seen in 1/3 runs · NEW — Code smells: the floor is the Chainlink price less maxSlippageBps; Chainlink updates only past a 0.5–2% deviation; any caller picks the block — Any caller can run the swap while the oracle lags the market, so the real loss bound is the deviation threshold plus maxSlippageBps. We did not measure a profitable case.
- **DexSwapModule.execute reverts on low output but soft-fails on router failure** — `DexSwapModule.execute` · seen in 1/3 runs · NEW — Code smells: `amountOut < oracleFloor` reverts with `DexSwapModule_InsufficientOutput`; a router failure returns `_failedResult`; the project rule says execute never reverts — The two failure branches behave differently. PaymentRails catches both, so we found no loss.
- **Short ForwardModule params make previewExecution revert with no reason** — `ForwardModule.validate` · seen in 1/3 runs · NEW — Code smells: `decodeParams` has no length check, unlike the other modules — The owner can store short params, and previewExecution then reverts with no reason. We found no loss of tokens.
- **Adding a wrapper needs a new factory and splits the registry** — `PaymentRailsFactory.create` · seen in 1/3 runs · KNOWN (2 scans) — Code smells: `wrappedNative` is fixed in the factory and in the CREATE2 init code — Every wrapper change needs a new PaymentRailsFactory, and registries that point at the old factory do not accept its rails. The fix is a redeploy.
- **Any caller can split one balance into many minimum-size actions** — `PaymentRails.executeAction` · seen in 3/3 runs · KNOWN (2 scans) — Code smells: the caller picks any amount at or above minBalance — Small CowSwap orders can stay unfilled until the owner cancels each one.
- **A caller-chosen gas limit makes the module call fail softly** — `PaymentRails.executeAction` · seen in 1/3 runs · NEW — Code smells: the module call is in try/catch, and the rail keeps 1/64 of the gas for the catch path — Any caller can make a scheduled action record a failure, and can block CowSwap order placement while they pay gas. We did not measure a working gas limit.
- **executeAction and previewExecution check the module in different ways** — `PaymentRails.executeAction` · seen in 2/3 runs · NEW — Code smells: preview checks module code length and execute does not — Re-confirmed present; no path that moves tokens.
- **Two swap routes that point at each other let any caller cycle a balance** — `PaymentRails.executeAction` · seen in 1/3 runs · NEW — Code smells: token A routes to B and B routes to A, with output to the rail — Any caller can loop the balance and lose up to maxSlippageBps on each leg. This needs an owner configuration we did not find.
- **previewExecution and executeAction run different checks** — `PaymentRails.previewExecution` · seen in 1/3 runs · NEW — Code smells: preview checks `token != 0` and module code length, runs `_checkNativePendingWrap`, and prices the whole balance; execute does none of these — A preview can revert for a call that executeAction accepts. We found no input where this moves tokens wrongly.
- **previewExecution rejects a DexSwap route whose balance is above maxAmount** — `PaymentRails.previewExecution` · seen in 2/3 runs · NEW — Code smells: the preview validates the whole balance — With balance 150 and maxAmount 100 the preview fails, but executeAction(100) succeeds.
- **The preview does not count native coin that waits unwrapped** — `PaymentRails.previewExecution` · seen in 1/3 runs · KNOWN (2 scans) — Code smells: `_checkNativePendingWrap` reverts only when the wrapped balance is short of minBalance — When the wrapped balance already meets minBalance, the preview ignores pending native coin. Re-confirmed present; no new mechanism.
- **A rail with no wrapper rejects the payments its exit would forward** — `PaymentRails.receive` · seen in 2/3 runs · KNOWN (2 scans) — Code smells: receive reverts when wrappedNative is zero, but the NatSpec says force-fed value can leave through sweepNative — Re-confirmed present; no new mechanism.
- **receive skips the NativeReceived event for every payment from the wrapper** — `PaymentRails.receive` · seen in 3/3 runs · NEW — Code smells: the `msg.sender != wrappedNative` branch; Arbitrum aeWETH `withdrawTo` pays any account from the wrapper — A third party on Arbitrum can pay the rail through `withdrawTo` with no NativeReceived event, so income totals miss it. We did not test it on a fork.
- **A zero-value payment reverts the payer's whole settlement** — `PaymentRails.receive` · seen in 1/3 runs · KNOWN (2 scans) — Code smells: receive reverts on `msg.value == 0` — A payer contract that sends zero value in a batch reverts the whole batch. Re-confirmed present; no new mechanism.
- **The sweep minimum binds only one of the two native paths** — `PaymentRails.sweepNative` · seen in 2/3 runs · KNOWN (2 scans) — Code smells: executeAction checks minBalance and sweepNative ignores it — Re-confirmed present; no new mechanism.
- **sweepNative unwraps all wrapped-native tokens, including routed and swap proceeds** — `PaymentRails.sweepNative` · seen in 3/3 runs · KNOWN (2 scans) — Code smells: the sweep withdraws the whole `wrappedNative` balance, including CowSwap and DexSwap proceeds — The owner sweep takes swap proceeds meant for a configured route. We did not confirm a deployment that sets both.
- **wrapNative can take a balance that an ERC20 route also reads** — `PaymentRails.wrapNative` · seen in 1/3 runs · NEW — Code smells: on Celo, zkSync Era and Polygon PoS the native coin also has an ERC20 view whose balanceOf is the native balance — Any caller can wrap a balance that the owner routed as an ERC20, so that route reverts. We did not confirm that a target chain uses both paths.
- **wrapNative reverts forever on a wrapper that rounds its credit** — `PaymentRails.wrapNative` · seen in 3/3 runs · KNOWN (2 scans) — Code smells: `credited != amount` and `received != wrapped` are strict equalities — A share-based wrapper that credits one wei less makes wrapNative revert on every call. We did not verify which target chains use such a wrapper.

---

## Known from earlier scans

_Recorded by earlier scans of this repo, not raised again by this one. Not re-checked — a record here may be fixed, or may still be live and missed. `.solidity-auditor/memory.tsv`._

| Scans | Kind | Location                                  | Title                                                        |
| ----- | ---- | ----------------------------------------- | ------------------------------------------------------------ |
| 1     | LEAD | `PaymentRailsFactory.createDeterministic` | One salt now gives a different rail address on each chain    |
| 1     | LEAD | `PaymentRailsFactory.create`              | Nothing checks that the wrapper is the chain's canonical one |
| 1     | LEAD | `PaymentRails.sweepNative`                | A low-gas call makes sweepNative report a false refusal      |

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
