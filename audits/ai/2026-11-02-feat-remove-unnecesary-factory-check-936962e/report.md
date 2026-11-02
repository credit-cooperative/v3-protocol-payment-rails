# 🔐 Security Review — v3-protocol-payment-rails

---

## Scope

|                                  |                                                                                                                                                                                                                                                                                                                            |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mode**                         | filename                                                                                                                                                                                                                                                                                                                   |
| **Files reviewed**               | `src/modules/contrib/bridges/AtumModuleFactory.sol` · `src/modules/contrib/bridges/AtumModule.sol` · `src/libraries/Errors.sol`<br>`scripts/solidity/deploy/DeployAtumModuleFactory.s.sol` · `scripts/solidity/deploy/DeployPaymentRailsFactory.s.sol` · `src/core/PaymentRails.sol`<br>`src/core/PaymentRailsFactory.sol` |
| **Confidence threshold (1-100)** | 75                                                                                                                                                                                                                                                                                                                         |
| **Passes**                       | 3                                                                                                                                                                                                                                                                                                                          |
| **Memory**                       | 0 records before this scan · 22 after · `936962e`                                                                                                                                                                                                                                                                          |

---

## Findings

[75] **1. The route guard counts any balance as staged funds**

`AtumModule._routeChangedWhileStaged` · Confidence: 75 · seen in 3/3 runs · NEW

**Description**
The guard treats any balance above zero as staged funds, so a refund or a donation blocks every execute on the new route.

**Fix (Option A — compare with the amount execute staged)**

```diff
-        return staged != keccak256(abi.encode(paymentParams)) && IERC20(token).balanceOf(address(this)) > 0;
+        return staged != keccak256(abi.encode(paymentParams)) && pendingAmount[token] > 0
+            && IERC20(token).balanceOf(address(this)) > 0;
```

**Fix (Option B — ignore a balance at or below a dust threshold)**

```diff
-        return staged != keccak256(abi.encode(paymentParams)) && IERC20(token).balanceOf(address(this)) > 0;
+        return staged != keccak256(abi.encode(paymentParams))
+            && IERC20(token).balanceOf(address(this)) > DUST_THRESHOLD;
```

---

[75] **2. A one wei donation blocks execute after a route change**

`AtumModule.execute` · Confidence: 75 · seen in 3/3 runs · NEW

**Description**
An attacker sends 1 wei to the module after a route change, so every execute call fails until the owner pauses and sweeps.

**Fix (Option A — validate against the staged amount)**

```diff
-        return staged != keccak256(abi.encode(paymentParams)) && IERC20(token).balanceOf(address(this)) > 0;
+        // Only funds that `execute` pulled count as staged. A donation or a refund alone does not.
+        return staged != keccak256(abi.encode(paymentParams)) && pendingAmount[token] > 0
+            && IERC20(token).balanceOf(address(this)) > 0;
```

**Fix (Option B — clear the stale route below a dust threshold)**

```diff
+        if (IERC20(token).balanceOf(address(this)) <= DUST_THRESHOLD) {
+            delete stagedRoute[token];
+        }
         if (_routeChangedWhileStaged(token, paymentParams)) {
             return _failedResult("Route changed while funds are staged");
         }
```

**Fix (Option C — let the keeper clear a settled route without a pause)**

```diff
+    /// @notice Clears the staged route once the keeper has settled the staged funds.
+    function clearStagedRoute(address token) external onlyKeeper {
+        delete stagedRoute[token];
+    }
```

---

Findings List

| #   | Confidence | Title                                                  |
| --- | ---------- | ------------------------------------------------------ |
| 1   | [75]       | The route guard counts any balance as staged funds     |
| 2   | [75]       | A one wei donation blocks execute after a route change |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **Chain-name validation checks only the prefix** — `AtumModule._decodeAndValidatePaymentParams` · seen in 2/3 runs · NEW — Code smells: `_hasChainPrefix` checks only the `chain/` prefix and not the case or format of `destinationChain`, so `Base` and `base` are two routes to the guard but may be one route to the keeper — The owner can stage a second route that the keeper reads as the same chain. We did not confirm how the keeper normalizes chain names.
- **A rounding token makes every execute revert** — `AtumModule._pullExactToken` · seen in 2/3 runs · NEW — Code smells: `received != amount` and `debited != amount` are strict equalities, and share-based rebasing tokens such as stETH move 1 or 2 wei less than requested — The module rejects any token with transfer rounding, so executeAction always fails for such a token while validate reports success. We did not confirm that the deployment configures such a token.
- **A failed pull reverts with a misleading error** — `AtumModule._pullExactToken` · seen in 1/3 runs · NEW — Code smells: a failed `_safeTransferFrom` reverts with `AtumModule_UnsupportedTokenReceivedAmount(amount, 0)`, which names a received-amount problem, and PaymentRails catches it as "Module execution reverted" — The module reverts with a misleading error when the transfer fails, so the log loses the real reason. We found no loss of tokens.
- **A late refund joins the new route's intent** — `AtumModule._routeChangedWhileStaged` · seen in 2/3 runs · NEW — Code smells: `stagedRoute` stays set after the balance reaches zero, and the emitted `available` is the raw balance — A refund that arrives after a route change becomes part of the new route's intent, so the keeper can pay route A funds to route B. We did not prove that an outside attacker controls the refund timing.
- **Repeated executeAction calls emit many intents for one balance** — `AtumModule.execute` · seen in 1/3 runs · NEW — Code smells: any caller can run executeAction with `amount = minBalance`, and each call emits `AtumIntentCreated` with the module's full balance — An attacker repeats executeAction, so the keeper receives many intents for one balance. We did not check whether the off-chain keeper removes duplicate intents.
- **pendingAmount stays high after Permit2 pulls tokens** — `AtumModule.execute` · seen in 3/3 runs · NEW — Code smells: `pendingAmount[token]` is written only by execute, syncAllowance and returnTokenBalance, and not when Permit2 pulls — An off-chain reader can see more staged tokens than the module holds. We did not find an on-chain reader that this harms.
- **The module cannot revoke an allowance stored inside Permit2** — `AtumModule.execute` · seen in 1/3 runs · NEW — Code smells: `isValidSignature` accepts any keeper-signed Permit2 digest, AllowanceTransfer permits included, and after `Permit2.permit` stores a spender allowance no ERC-1271 call happens again, while the module has no path to `Permit2.approve(…, 0)` or `lockdown` — A spender that holds a keeper-signed AllowanceTransfer permit can pull the module balance after unpause, because pause and invalidateDigest do not reach Permit2. We did not confirm that the keeper ever signs AllowanceTransfer permits.
- **A refund for the old route pays out to the new route** — `AtumModule.execute` · seen in 3/3 runs · NEW — Code smells: `stagedRoute` is overwritten on each successful execute, the guard treats a zero balance as settled, and an inbound Escrow refund is tied to no route — A refund for route A that arrives after route B is staged goes to route B's destination. The source documents this, and we did not find a path where an attacker picks the refund timing.
- **The route guard treats two spellings of one destination as two routes** — `AtumModule.execute` · seen in 1/3 runs · NEW — Code smells: `stagedRoute` stores the hash of the three raw strings, and `_hasChainPrefix` checks only a byte prefix with no normalization — A change in letter case alone counts as a route change while funds are staged. We did not confirm whether the Atum keeper normalizes these strings off-chain.
- **An unused old-route digest can spend funds staged for a new route** — `AtumModule.execute` · seen in 1/3 runs · NEW — Code smells: the guard accepts a new route when the balance is 0, execute then sets `forceApprove(permit2, available)`, and a keeper digest signed for the old route stays valid until someone calls `invalidateDigest` — Any holder of an unused keeper digest for the old route can pull funds that a later execute stages for the new route. We did not prove that Escrow accepts such a digest after the route changes.
- **A contract keeper's own signing rules decide every Permit2 pull** — `AtumModule.isValidSignature` · seen in 1/3 runs · NEW — Code smells: the module calls `keeper.isValidSignatureNow(hash, signature)`, so a contract-wallet keeper's ERC-1271 answer is accepted and that wallet sees the module as the caller — A keeper contract wallet can approve a hash for any module that names it. We did not check any real keeper wallet.
- **Two modules with one keeper accept the same Permit2 signature** — `AtumModule.isValidSignature` · seen in 3/3 runs · NEW — Code smells: the check covers only the keeper signature and the caller allowlist, and the Permit2 digest does not include the module owner — A request signed for one module validates on another module that shares the keeper. The comment says the Escrow depositId check stops this, and we did not verify that check.
- **The next execute after unpause restores the full Permit2 allowance** — `AtumModule.returnTokenBalance` · seen in 3/3 runs · NEW — Code smells: `_returnTokenBalance` zeroes the allowance and clears `stagedRoute`, the next execute or syncAllowance sets the allowance back to the full balance, and the pause invalidates no keeper digest — An old keeper digest that nobody invalidated can pull the new balance after unpause. We did not confirm that Atum Escrow accepts such a digest.
- **A zero-balance token can fail the whole returnTokenBalances batch** — `AtumModule.returnTokenBalances` · seen in 3/3 runs · NEW — Code smells: `_returnTokenBalance` calls `safeTransfer` even when the amount is 0, and the batch loop stops at the first revert — A token that reverts on a zero transfer, or a blacklisted module address, makes the batch fail for every listed token. The owner can call returnTokenBalance per token as a workaround.
- **A keeper rotation back to an old key revives its digests** — `AtumModule.setKeeper` · seen in 2/3 runs · NEW — Code smells: `setKeeper` only replaces `keeper`, and `isValidSignature` checks only `_invalidatedPermitDigests` and the current keeper, so nothing ties a signature to the keeper term that signed it — The owner who rotates the keeper back to an old key makes every digest that key signed, and nobody invalidated, valid again. We did not prove that Permit2 nonce or deadline state leaves such a digest usable.
- **syncAllowance raises the allowance with no route check** — `AtumModule.syncAllowance` · seen in 3/3 runs · NEW — Code smells: it writes `pendingAmount` and the Permit2 allowance but never reads or writes `stagedRoute` — The keeper can approve refunded old-route tokens after a route change, and no route check runs. The source calls this a known limit, so we did not prove a wrong destination without a keeper error.
- **A direct validate call checks the caller's balance** — `AtumModule.validate` · seen in 3/3 runs · NEW — Code smells: `_hasSufficientBalance` reads `balanceOf(msg.sender)`, so a caller other than PaymentRails is checked against its own balance — The preview result can differ from what execute does when a caller other than PaymentRails calls validate. We found no on-chain caller that depends on this result.
- **previewExecution passes a token that execute always rejects** — `AtumModule.validate` · seen in 1/3 runs · NEW — Code smells: `validate` does not simulate `_pullExactToken`, so a token that moves a different amount passes the preview and then reverts in execute — previewExecution reports success for a fee or rounding token, but every execute reverts for that token. We did not find a deployment that uses such a token.
- **Any caller picks the time and amount of executeAction** — `PaymentRails.executeAction` · seen in 3/3 runs · NEW — Code smells: no caller check, `amount` is checked only against `minBalance`, and each call resets the Permit2 allowance to the full balance and emits a new `AtumIntentCreated` — Any caller can run executeAction just before an owner route change, so the module stages funds under the old route and the new route fails. We did not show a theft path, because Permit2 still needs a keeper signature.
- **previewExecution checks the module code but executeAction does not** — `PaymentRails.executeAction` · seen in 1/3 runs · NEW — Code smells: previewExecution checks `config.actionModule.code.length == 0` and validates with the full balance, while executeAction skips the code check and uses the caller's amount — A configured module with no code makes the try-call revert in a way the catch does not handle. We did not prove a reachable state where a configured module has no code.

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
