# 🔐 Security Review — v3-protocol-payment-rails

---

## Scope

|                                  |                                                                                                                                                                                                                                                                                                                                               |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mode**                         | filename                                                                                                                                                                                                                                                                                                                                      |
| **Files reviewed**               | `./src/core/PaymentRails.sol` · `./src/core/PaymentRailsFactory.sol` · `./src/interfaces/IPaymentRails.sol`<br>`./src/interfaces/IPaymentRailsFactory.sol` · `./src/libraries/Errors.sol` · `./src/types/DataTypes.sol`<br>`./scripts/solidity/deploy/DeployPaymentRails.s.sol` · `./scripts/solidity/deploy/DeployPaymentRailsFactory.s.sol` |
| **Confidence threshold (1-100)** | 75                                                                                                                                                                                                                                                                                                                                            |
| **Passes**                       | 3 (pass 1 ran 10/12 agents, pass 2 ran 11/12 agents)                                                                                                                                                                                                                                                                                          |
| **Memory**                       | 35 records before this scan · 50 after · `31daba6`                                                                                                                                                                                                                                                                                            |

---

## Findings

[75] **1. AtumModuleFactory rejects every rail from a PR #23 factory**

`AtumModuleFactory.create` · Confidence: 75 · seen in 3/3 runs · KNOWN (2 scans)

**Description**
The Sepolia AtumModuleFactory returns the deprecated `0x0000DD52…` from `paymentRailsFactory()`, so the owner cannot attach an Atum module to any rail from a new factory.

**Fix (Option A — redeploy)**

```diff
  // PR #23 rollout, per chain:
  // 1. deploy PaymentRailsFactory(owner) from the final hold-and-sweep commit
+ // 2. deploy AtumModuleFactory(owner, ..., newPaymentRailsFactory)
+ // 3. record both in deployments/<chainId>.json in the same change
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

[75] **2. The Sepolia record names a factory built from the rejected wrap design**

`PaymentRailsFactory.create` · Confidence: 75 · seen in 3/3 runs · NEW

**Description**
The uncommitted Sepolia record lists factory `0x6f0554db…` as current, and its on-chain bytecode holds `wrapNative()`, so operators create rails that are not PR #23.

**Fix**

```diff
     "PaymentRailsFactory": {
-      "address": "0x6f0554db96a8ff4bce0d9fa4f7012a8b8c96a549",
-      "commit": "31daba6",
-      "constructorArgs": [
-        "0x023A86c6e2fA035172f0106356cf5E27837c0b28",
-        "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
-      ],
+      "address": "<factory deployed from the final hold-and-sweep commit>",
+      "commit": "<final PR #23 commit>",
+      "constructorArgs": ["0x023A86c6e2fA035172f0106356cf5E27837c0b28"],
       "history": [
+        { "address": "0x6f0554db96a8ff4bce0d9fa4f7012a8b8c96a549", "commit": "31daba6", "deprecated": "<date>" },
```

---

Findings List

| #   | Confidence | Title                                                                  |
| --- | ---------- | ---------------------------------------------------------------------- |
| 1   | [75]       | AtumModuleFactory rejects every rail from a PR #23 factory             |
| 2   | [75]       | The Sepolia record names a factory built from the rejected wrap design |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **The CCTP fee cap rounds down and can fall one unit short** — `CCTPBridgeModule._validateBridgeParams` · seen in 1/3 runs · KNOWN (2 scans) — Code smells: `amount * maxFeeBps / 10_000` rounds down — A small bridge amount gets a cap below the Circle fee. We did not check the Circle rule on a fork.
- **The oracle floor rounds down twice on small amounts** — `DexSwapModule._computeOracleFloor` · seen in 1/3 runs · KNOWN (2 scans) — Code smells: at expected = 2 the floor is 1, an allowance near 5,000 bps — Any caller who picks a small amount gets a floor far below maxSlippageBps. The value per call is dust.
- **predictDeterministicAddress uses the EVM CREATE2 formula on zkSync too** — `PaymentRailsFactory.createDeterministic` · seen in 1/3 runs · NEW — Code smells: zkSync Era derives CREATE2 addresses another way; foundry.toml lists a zksync RPC — A payer who pre-funds a predicted address on zkSync sends coin to an address no rail occupies. We did not confirm that zkSync is a target. This is also on main.
- **Each change to the rail code needs a new factory and splits the registry** — `PaymentRailsFactory.create` · seen in 2/3 runs · KNOWN (3 scans) — Code smells: the factory bakes the PaymentRails creation code; provenance checkers hold the old factory address — Every rail-code change needs a new factory and a redeploy of each checker. The fix is operational.
- **TokenConfigured omits minBalance, enabled and moduleParams** — `PaymentRails.configureToken` · seen in 1/3 runs · NEW — Code smells: the event logs token, actionType and actionModule only; the clear branch still stores the passed fields — The owner can change the forward recipient, and a monitor that reads only events misses the change.
- **Any caller can split one balance into many minimum-size actions** — `PaymentRails.executeAction` · seen in 3/3 runs · KNOWN (3 scans) — Code smells: minBalance limits the caller amount; with minBalance 0, chunks reach the module rounding edges — We did not find a split that pays more than gas.
- **ActionExecuted reports the full amount for a fee-on-transfer forward** — `PaymentRails.executeAction` · seen in 1/3 runs · NEW — Code smells: ForwardModule returns amountOut = amount with no balance-delta check; the fee-on-transfer exclusion names only the swap modules — The event and the tokens the recipient gets disagree for a fee-on-transfer token.
- **A caller-chosen gas limit makes the module call fail softly** — `PaymentRails.executeAction` · seen in 2/3 runs · KNOWN (2 scans) — Code smells: the module call is in try/catch; the rail keeps 1/64 of the gas — Any caller can make the rail log a false ActionFailed. DexSwapModule returns the input, so nobody profits.
- **executeAction and previewExecution check the module in different ways** — `PaymentRails.executeAction` · seen in 2/3 runs · KNOWN (2 scans) — Code smells: preview checks module code length and uses the full balance; execute checks neither — A passing preview does not prove that execution passes.
- **A module that returns undecodable data makes executeAction revert** — `PaymentRails.executeAction` · seen in 3/3 runs · NEW — Code smells: the ExecutionResult decode runs in the rail frame, outside the catch — Only an owner-configured module can trigger this. Re-confirmed present.
- **A token that rejects a zero approve makes executeAction revert** — `PaymentRails.executeAction` · seen in 1/3 runs · NEW — Code smells: all three result branches call `forceApprove(module, 0)`; BNB on Ethereum reverts on a zero approve — The route for such a token never runs, and the soft-failure path reverts too. We found no such token in any planned config.
- **previewExecution and executeAction run different checks** — `PaymentRails.previewExecution` · seen in 3/3 runs · KNOWN (2 scans) — Code smells: preview checks the full balance; execute checks the caller amount — Re-confirmed present.
- **The rail rejects a native payment that carries calldata** — `PaymentRails.receive` · seen in 3/3 runs · NEW — Code smells: the rail has `receive()` and no payable `fallback()` — A payer that attaches a memo or invoice id gets a revert. We did not confirm how Rain sends AVAX.
- **Native value can arrive with no NativeReceived event** — `PaymentRails.receive` · seen in 3/3 runs · NEW — Code smells: selfdestruct, coinbase credits and payments to a predicted CREATE2 address skip receive; 1-wei payments add noise — The swept total can exceed the logged receipts. Only off-chain reconciliation sees the gap.
- **The rail now accepts native output that main rejected** — `PaymentRails.receive` · seen in 2/3 runs · NEW — Code smells: no in-tree module sends native coin; CowSwap rejects the 0xEeee buy marker at `_getTokenDecimals` — Native output from a future module or a third-party order waits for an owner sweep. No live path today.
- **The 2300-gas stipend is proven only under shanghai gas rules** — `PaymentRails.receive` · seen in 3/3 runs · NEW — Code smells: foundry.toml pins shanghai; receive costs about 1.4k–1.55k gas; Sepolia and Avalanche gas rules differ — A `transfer` payer can revert under a LOG repricing that no test measures.
- **A low-gas sweep blames the recipient for the failure** — `PaymentRails.sweepNative` · seen in 3/3 runs · KNOWN (2 scans) — Code smells: every recipient-call failure maps to `PaymentRails_NativeTransferFailed(recipient)` — The owner sees the wrong error, but no coin is lost.
- **On a chain with an ERC20 view of the native coin, two paths read one balance** — `PaymentRails.sweepNative` · seen in 3/3 runs · NEW — Code smells: Celo, Polygon PoS 0x…1010 and zkSync 0x…800A expose the native balance through balanceOf — Any caller can route held native coin through executeAction if the owner configures that address. Avalanche does not have this view.
- **Native receivables leave only to a recipient the owner picks at each sweep** — `PaymentRails.sweepNative` · seen in 3/3 runs · NEW — Code smells: no stored destination for native coin, unlike ERC20 routes — Payees cannot check on chain where native receivables go. This is the accepted design.
- **sweepNative logs an outflow for value that comes back to the rail** — `PaymentRails.sweepNative` · seen in 3/3 runs · NEW — Code smells: `recipient == address(this)` passes; a recipient can return value through receive, which has no lock; `sweepNative(WAVAX)` wraps the AVAX back to the rail as WAVAX — NativeSwept reports more value than left the rail. The WAVAX case may be the intended way to route native receivables, so state it in the docs.
- **An attacker can change the amount of a queued Safe sweep** — `PaymentRails.sweepNative` · seen in 1/3 runs · NEW — Code smells: `amount = address(this).balance` is read at execution; signers approve only `recipient`; Safe transactions wait in a public queue — An attacker who sends 1 wei before the sweep changes the amount, so a recipient that needs an exact value rejects every sweep. No in-repo recipient needs an exact value.
- **sweepNative reverts on a zero balance while receive ignores zero** — `PaymentRails.sweepNative` · seen in 1/3 runs · NEW — Code smells: receive treats zero as a no-op so a batch does not fail; sweepNative reverts with `PaymentRails_ZeroNativeBalance` — An owner Safe batch that sweeps many rails reverts when one rail holds no coin. Only the owner is affected.

---

## Known from earlier scans

_Recorded by earlier scans of this repo, not raised again by this one. Not re-checked — a record here may be fixed, or may still be live and missed. `.solidity-auditor/memory.tsv`._

| Scans | Kind    | Location                                  | Title                                                                        |
| ----- | ------- | ----------------------------------------- | ---------------------------------------------------------------------------- |
| 1     | LEAD    | `atummodule.execute`                      | A 1-wei transfer blocks the next Atum route change                           |
| 1     | LEAD    | `atummodule.execute`                      | Permit2 pulls never lower pendingAmount                                      |
| 1     | LEAD    | `atummodule.syncallowance`                | Any caller can raise the Atum Permit2 allowance through executeAction        |
| 1     | LEAD    | `cctpbridgemodule.execute`                | CCTP execute reports the fee cap as the bridge cost                          |
| 1     | LEAD    | `cctpbridgemodule.execute`                | Any caller can call the CCTP bridge execute directly                         |
| 1     | LEAD    | `cctpbridgemodule.validate`               | validate accepts a CCTP fee cap that depositForBurn can reject               |
| 1     | LEAD    | `cowswapmodulefactory.-checkcreateparams` | CowSwapModuleFactory checks the rail less than AtumModuleFactory does        |
| 1     | LEAD    | `cowswapmodule.-computeexpectedoutput`    | A decimal gap of 78 or more makes validate panic                             |
| 1     | LEAD    | `cowswapmodule.-validateswapparams`       | CowSwapModule accepts a slippage near 10_000 bps                             |
| 1     | LEAD    | `cowswapmodule.cancelorder`               | Expired CowSwap orders keep their tokens until the owner cancels each one    |
| 1     | LEAD    | `cowswapmodule.cancelorder`               | cancelOrder refunds from the balance that all pending orders share           |
| 1     | LEAD    | `cowswapmodule.constructor`               | A direct CowSwapModule deploy skips the factory sequencer checks             |
| 1     | LEAD    | `cowswapmodule.execute`                   | CowSwap orders use one maxStaleness value for two feeds                      |
| 1     | LEAD    | `cowswapmodule.execute`                   | A solver can fill a CowSwap order at an old oracle floor                     |
| 1     | LEAD    | `dexswapmodule.-executeswap`              | The swap deadline uses the current block time                                |
| 1     | LEAD    | `dexswapmodule.-executeswap`              | A very large swapDeadlineSeconds passes validate and overflows in execute    |
| 1     | LEAD    | `dexswapmodule.-executeswap`              | A falling target balance makes the swap spend the input and report failure   |
| 1     | LEAD    | `dexswapmodule.-getoracleprice`           | One maxStaleness value covers two feeds with different heartbeats            |
| 1     | LEAD    | `dexswapmodule.-validateparams`           | DexSwapModule accepts maxSlippageBps of 10_000                               |
| 1     | LEAD    | `dexswapmodule.constructor`               | DexSwapModule accepts a sequencer feed with a zero grace period              |
| 1     | LEAD    | `dexswapmodule.execute`                   | The swap loss can exceed maxSlippageBps by the feed deviation threshold      |
| 1     | LEAD    | `dexswapmodule.execute`                   | DexSwapModule.execute reverts on low output but soft-fails on router failure |
| 1     | FINDING | `dexswapmodule.execute`                   | Any caller of DexSwapModule.execute takes the whole sell-token balance       |
| 1     | LEAD    | `forwardmodule.validate`                  | Short ForwardModule params make previewExecution revert with no reason       |
| 1     | LEAD    | `PaymentRails.executeAction`              | Two swap routes that point at each other let any caller cycle a balance      |
| 1     | LEAD    | `PaymentRails.previewExecution`           | previewExecution rejects a DexSwap route whose balance is above maxAmount    |

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
