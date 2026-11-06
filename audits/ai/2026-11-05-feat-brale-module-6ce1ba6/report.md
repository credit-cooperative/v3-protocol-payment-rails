# 🔐 Security Review — v3-protocol-payment-rails

---

## Scope

|                                  |                                                                                              |
| -------------------------------- | -------------------------------------------------------------------------------------------- |
| **Mode**                         | filename                                                                                     |
| **Files reviewed**               | `src/modules/redemptions/BraleModule.sol` · `src/modules/redemptions/BraleModuleFactory.sol` |
| **Confidence threshold (1-100)** | 75                                                                                           |
| **Passes**                       | 3                                                                                            |
| **Memory**                       | 22 records before this scan · 34 after · `6ce1ba6`                                           |

---

## Findings

[75] **1. Any caller can split the rails balance into many small redemptions**

`BraleModule.execute` · Confidence: 75 · seen in 3/3 runs · NEW

**Description**
The module accepts any amount above zero, so any caller of `executeAction` splits one balance into many redemptions that pay a Brale fee each, stay below the Brale minimum, or convert to zero USDC.

**Fix (Option A — validate)**:

```diff
     struct BraleRedemptionParams {
         address depositAddress;
         address outputToken;
+        uint256 minAmount;
     }
@@ BraleModule._validate
-        if (params.length < 64) return (false, "Invalid params encoding", p);
+        if (params.length < 96) return (false, "Invalid params encoding", p);
@@
         if (p.depositAddress == p.outputToken) return (false, "Deposit address is output token", p);
+        if (amount < p.minAmount) return (false, "Below minimum redemption", p);
```

**Fix (Option B — restrict)**:

```diff
-    function executeAction(address token, uint256 amount) external nonReentrant returns (bool success) {
+    function executeAction(address token, uint256 amount) external nonReentrant onlyExecutor returns (bool success) {
```

**Fix (Option C — ban-path)**:

```diff
+        if (amount != IERC20(token).balanceOf(msg.sender)) return _failedResult(token, "Partial redemption");
         uint256 nonce = redemptionNonce;
```

**Fix (Option D — validate par output)**:

```diff
         if (p.depositAddress == p.outputToken) return (false, "Deposit address is output token", p);
+        (uint256 parOut,) = this.estimateOutput(token, amount, params);
+        if (parOut == 0) return (false, "Zero par output", p);
```

---

Findings List

| #   | Confidence | Title                                                              |
| --- | ---------- | ------------------------------------------------------------------ |
| 1   | [75]       | Any caller can split the rails balance into many small redemptions |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **The preview prices every token at one US dollar** — `BraleModule.estimateOutput` · seen in 3/3 runs · NEW — Code smells: no input-token allowlist; `amount / 10 ** down` truncates to 0; the overflow branch returns 0 as a sentinel; invalid params return `(0, token)`. — `estimateOutput` returns gross 1:1 par for any token, ignores the Brale fee and minimum, and returns 0 on truncation or overflow while `execute` still sends the tokens.
- **A token that rounds by one wei makes every execute revert** — `BraleModule.execute` · seen in 3/3 runs · NEW — Code smells: strict equality on both balance deltas; no tolerance. — The checks `delivered != amount` and `debited != amount` revert on a one-wei difference, so a share-based token can never be redeemed while `validate` still passes it.
- **A failed transfer does not check that no tokens moved** — `BraleModule.execute` · seen in 3/3 runs · NEW — Code smells: `depositBefore` and `railsBefore` are not compared on the failure branch. — When `_safeTransferFrom` returns false, the module restores the nonce without a check of the balance snapshots, so a token that moves funds and returns false leaves tokens at Brale with no event.
- **A low gas limit makes execute report a false failure** — `BraleModule.execute` · seen in 3/3 runs · NEW — Code smells: `try this.decodeParams` and `trySafeTransferFrom` treat out-of-gas as a normal failure; no `gasleft()` floor. — Any caller sets the gas limit, so the `this.decodeParams` self-call or the token transfer can run out of gas and the rails logs a false reason. One agent calculated that the outer calls fail first for a standard token.
- **A reorg moves a redemptionId to a different amount** — `BraleModule.execute` · seen in 1/3 runs · NEW — Code smells: `token`, `amount` and `depositAddress` are not in the id; README section 4 stores the first sight before finality. — The redemptionId hashes only chain, module and nonce, so after a reorg an attacker transaction takes the nonce and the service refuses the real redemption. We did not verify how the service stores ids before finality.
- **The borrower can withdraw tokens from the custodial wallet before the swap** — `BraleModule.execute` · seen in 2/3 runs · NEW — Code smells: no on-chain return path for the USDC; README section 6 expects a borrower-initiated outflow; README section 12 question 2 is open. — The module sends tokens to the borrower's Brale custodial wallet before the off-chain swap, so a borrower with withdrawal access takes them out first. Brale has not confirmed what access the borrower has.
- **execute reports zero output while the preview shows the full amount** — `BraleModule.execute` · seen in 1/3 runs · NEW — Code smells: `_successResult(0, p.outputToken, ...)` on every success. — `execute` returns `amountOut = 0`, so every `ActionExecuted` event records zero output while `previewExecution` shows the par value. No on-chain consumer reads it.
- **The amount checks revert, so the rails event loses the reason** — `BraleModule.execute` · seen in 2/3 runs · NEW — Code smells: two failure styles for one kind of fault; `PaymentRails.executeAction` drops the revert data. — An amount mismatch reverts with a typed error, so the rails catch logs only "Module execution reverted" and the operator cannot see the cause. No funds move.
- **Two redemptions in one transaction share one tx hash** — `BraleModule.execute` · seen in 3/3 runs · NEW — Code smells: README section 6 does not match on (tx hash, log index); no rule marks a matched deposit as used; a third party can add its own transfer in the same transaction. — An attacker contract puts several equal redemptions in one transaction, so the service match on tx hash, amount and token cannot pair each event with its own deposit.
- **validate passes a fee-on-transfer token that execute always rejects** — `BraleModule.validate` · seen in 2/3 runs · NEW — Code smells: the exact-amount checks exist only in `execute`. — `_validate` does not check the transfer behaviour of the token, so `previewExecution` reports a valid route for a fee-on-transfer token while every `execute` reverts.
- **The off-chain kill switch does not stop on-chain redemptions** — `PaymentRails.executeAction` · seen in 1/3 runs · NEW — Code smells: README step 7 (`configureToken` with enabled true) comes before step 8 (registry write); the borrower may control the custodial wallet. — The service kill switch and registry row exist only off-chain, so any caller still moves the rails balance into the borrower wallet while the service refuses to swap.
- **Any caller picks the time and amount of executeAction** — `PaymentRails.executeAction` · seen in 2/3 runs · KNOWN (2 scans) — Code smells: no caller check; the owner has no single-step disable-and-drain. — Any caller watches for a `configureToken` call that rotates the deposit address and calls `executeAction` first, so the full balance goes to the old Brale address.

---

## Resolution

_Added after the scan. The scan ran on the uncommitted `feat/brale-module` working tree on top of `6ce1ba6`, with 12 Opus agents per pass._

- **Finding 1 (no minimum redemption amount): fixed with Option A.** `BraleRedemptionParams` gains a third field, `minAmount`. `BraleModule._validate` now requires at least 96 bytes of params, rejects `minAmount == 0` and rejects `amount < minAmount`. A rejected call returns a failed result before the nonce or any transfer. Unit tests cover each case.
- **Lead "The off-chain kill switch does not stop on-chain redemptions": mitigated in the runbook.** `src/modules/redemptions/README.md` now registers the borrower with the service before `configureToken(enabled=true)`, and documents pause and offboard as `configureToken(enabled=false)` first, then the off-chain flag.
- **Leads that depend on Brale answers** (custodial-wallet withdrawal, same-transaction deposit matching, reorg id reassignment) are tracked as open questions in the README, section 12, and in the off-chain service spec.
- **Rejected at the gate (owner-only, no unprivileged path):** unallowlisted input token, non-canonical params bytes, stale registry owner in the factory event, factory accepts any contract as rails, unbounded `decimals()` gas, output token with no code.

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
