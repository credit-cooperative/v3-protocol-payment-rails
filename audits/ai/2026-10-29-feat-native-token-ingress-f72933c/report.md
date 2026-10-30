# 🔐 Code Review — v3-protocol-payment-rails

---

## Scope

|                  |                                                                                                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Date**         | 2026-10-29                                                                                                                                                         |
| **Tool**         | Claude Code `/code-review`, effort `high`, one reviewer agent                                                                                                      |
| **Branch**       | `feat/native-token-ingress` (PR #23)                                                                                                                               |
| **Commit**       | `f72933c` — reviewed range `main...f72933c` (`73b2fdd`, `9c83825`, `f72933c`)                                                                                      |
| **Files**        | `src/core/PaymentRails.sol`, `src/core/PaymentRailsFactory.sol`, interfaces, `Errors.sol`, deploy scripts, both bash harnesses, new unit / invariant / fork suites |
| **Prior review** | [`2026-10-26-feat-native-token-ingress-9c83825`](../2026-10-26-feat-native-token-ingress-9c83825/report.md) (solidity-auditor, 3 passes)                           |
| **Why this run** | Independent review after `f72933c` made `wrapNative` owner-only, before the Sepolia deploy                                                                         |
| **Follow-up**    | `31daba6` — fixes findings 5, 6 and 7 and documents finding 1                                                                                                      |

Line numbers refer to `f72933c`.

---

## Findings

**1. `sweepNative` is all-or-nothing and depends on the wrapper's `withdraw`**

`PaymentRails.sweepNative` · `src/core/PaymentRails.sol:116` · Status: **OPEN — design decision pending**, risk documented in `31daba6`

**Description**
The sweep always unwraps the entire `wrappedNative` balance before paying out, so there is no way to sweep only raw native.

**Failure scenario**
The rail holds 100 WAVAX of swap proceeds waiting for a route and 0.3 AVAX of force-fed dust. Sweeping the dust burns all 100 WAVAX and pays 100.3 AVAX to the recipient. On a chain whose wrapper is an upgradeable predeploy (Arbitrum aeWETH), a paused or reverting `withdraw` also blocks recovery of the raw native, because the unwrap runs before the payout.

**Fix options**

- Add a `skipUnwrap` flag or an explicit amount to `sweepNative`.
- Deploy only against immutable WETH9-style wrappers (WETH9, WAVAX). `31daba6` states this rule in SECURITY.md and `DeployPaymentRailsFactory.s.sol`.

---

**2. Owner-only `wrapNative` fixes the race at the wrong layer**

`PaymentRails.wrapNative` · `src/core/PaymentRails.sol:73` · Status: **ACKNOWLEDGED — kept by team decision (2026-10-29)**

**Description**
The reviewer argues the wrap-then-execute race is harmless because the route is owner-configured. Gating the wrap puts every native payment behind a multi-sig transaction, and the already-wrapped balance can still be routed ahead of a sweep.

**Failure scenario**
Rain's Coordinator pays AVAX each settlement cycle. Each payment now sits idle until the Safe signs `wrapNative()`, and only then can the keeper route the WAVAX.

**Response**
The team chose owner-only wrap so native value moves only where the owner sends it, matching `configureToken` and `sweepNative`. The latency cost is accepted. A dedicated wrapper role remains the alternative if a Safe signature per wrap is too slow for Rain's cadence.

---

**3. `receive()` reverts on a zero-value payment**

`PaymentRails.receive` · `src/core/PaymentRails.sol:61` · Status: **OPEN — design decision pending**, listed as accepted in SECURITY.md

**Description**
A zero-value call reverts with `PaymentRails_ZeroAmount`, which a third-party payer may treat as a failed payment.

**Failure scenario**
A settlement contract pays N recipients in one transaction and reverts on any failed call. If the rail's share rounds to 0 wei, the whole batch reverts and every other recipient is blocked.

**Fix**
Return early without emitting `NativeReceived` when `msg.value == 0`. This keeps the "every event is a balance increase" property without reverting the payer.

---

**4. The preview's wrap hint is only actionable by the owner and fires inconsistently**

`PaymentRails._checkNativePendingWrap` · `src/core/PaymentRails.sol:228` · Status: **ACKNOWLEDGED — documented**

**Description**
`previewExecution` reverts `PaymentRails_NativePendingWrap` to tell a keeper to wrap, but only the owner can wrap. It also says nothing about pending native once the wrapped balance meets `minBalance`.

**Failure scenario**
With 0 WAVAX and 5 AVAX pending, the keeper gets the hint and cannot act on it. With 1 WAVAX and 5 AVAX pending, the preview returns an estimate for 1 WAVAX and stays silent about the rest.

**Response**
`f72933c` changed the hint's NatSpec to say the owner must wrap. The silent case is listed in SECURITY.md. Off-chain tooling should also read the rail's native balance directly.

---

**5. `sweepNative` runs the unwrap before its "something to sweep" check**

`PaymentRails.sweepNative` · `src/core/PaymentRails.sol:126` · Status: **FIXED in `31daba6`**

**Description**
The unwrap interaction ran before the zero-balance check, breaking the repo's CEI convention.

**Fix applied**
The wrapped balance is read first and `native + wrapped == 0` reverts before any external call. Behaviour and errors are unchanged.

---

**6. The preview-native suite never tests `minBalance == 0`**

`tests/unit/concrete/payment-rails/preview-execution-native/PreviewExecutionNative.t.sol:9` · Status: **FIXED in `31daba6`**

**Description**
Every case used a 1-ether minimum, but the fork test and IMPLEMENTATION.md configure `minBalance = 0`. A regression in the `balance == 0 ||` half of the condition would have passed the suite.

**Fix applied**
Two cases under `givenWrappedConfiguredWithZeroMin`. Pending native with no wrapped balance reverts `NativePendingWrap`, and any wrapped balance previews on its own.

---

**7. The Sepolia test setup deploys a rail with native ingress disabled**

`scripts/solidity/deploy/DeploySepoliaTestSetup.s.sol:62` · Status: **FIXED in `31daba6`**

**Description**
The setup passed `wrappedNative = address(0)`, so the testnet rehearsal bounced all native value and never ran the feature.

**Fix applied**
The setup passes Sepolia WETH9 `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14`.

---

## Findings List

| #   | Location                               | Title                                                         | Status                  |
| --- | -------------------------------------- | ------------------------------------------------------------- | ----------------------- |
| 1   | `PaymentRails.sweepNative`             | Sweep is all-or-nothing and depends on the wrapper's withdraw | Open (decision pending) |
| 2   | `PaymentRails.wrapNative`              | Owner-only wrap fixes the race at the wrong layer             | Acknowledged            |
| 3   | `PaymentRails.receive`                 | Zero-value payment reverts the payer                          | Open (decision pending) |
| 4   | `PaymentRails._checkNativePendingWrap` | Preview wrap hint is owner-only and inconsistent              | Acknowledged            |
| 5   | `PaymentRails.sweepNative`             | Unwrap runs before the zero check (CEI)                       | Fixed `31daba6`         |
| 6   | `PreviewExecutionNative.t.sol`         | No test for `minBalance == 0`                                 | Fixed `31daba6`         |
| 7   | `DeploySepoliaTestSetup.s.sol`         | Sepolia setup disables native ingress                         | Fixed `31daba6`         |

---

## Checked and clean

- `receive()` costs 1,587 gas on the optimized build, so `transfer` / `send` payers and WETH9-style `withdraw` payouts fit the 2,300 stipend.
- Every `new PaymentRails(...)` and `run(address)` call site, doc and harness was updated for the new constructor argument.
- `predictDeterministicAddress` covers the new constructor argument, and the fork test proves it.
- CowSwap keeps sell-token custody in the module, so a sweep cannot strand a pending order.
- The Avalanche fork suite exercises real WAVAX `deposit` / `withdraw`, including the stipend payout, and a real SwapRouter02 swap.

---

## Verification after `31daba6`

- CI on `31daba6` is green: build, lint and format, tests, coverage.
- Avalanche dress rehearsal: 74 passed, 0 failed. e2e Anvil harness on a mainnet fork: 142 passed, 0 failed.
- Factory deployed on Sepolia at `0x6f0554DB96A8fF4bCE0D9fA4F7012a8b8c96a549` from `31daba6`, with owner and `wrappedNative` checked on-chain.

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended.
