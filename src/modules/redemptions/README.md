# Brale redemption module: off-chain service spec and onboarding runbook

`BraleModule` sends a Brale-issued token (for example SBC) from a PaymentRails to the borrower's Brale deposit address and emits `RedemptionInitiated`. An off-chain service turns each event into a Brale swap transfer that delivers USDC back to the same PaymentRails. The contract does no swapping. Anything marked **unconfirmed** must be checked against the Brale dashboard or with Brale before mainnet.

## 1. Model and trust

- One borrower = one PaymentRails = one `BraleModule` (made by `BraleModuleFactory`) = one Brale managed **custodial business** account (`account_id`). The borrower's custodial internal wallet is that rails' `depositAddress`.
- The event is a hint. Brale's credited deposit on the borrower account is the truth.
- The service registry (section 3) is the only source for the `rails <-> account` binding. The contracts do not know `account_id`.

## 2. Borrower onboarding runbook

Manual, using the **onboarding key** (section 11). Run the steps in this order.

1. `POST /accounts` with an `Idempotency-Key` (UUID, recorded in the runbook log); scope `accounts:write`.
   - Create a **business** account of **custodial** type, with `tos_attestation` recording the borrower's acceptance of the **Brale End-User Agreement**. The agreement must actually be shown to the borrower.
   - Exact field names: see the Brale API reference (**unconfirmed**; check the dashboard or ask Brale).
   - Record the returned `account_id`.
2. Wait for the `account.verification.completed` webhook, or poll `GET /accounts/{borrower_account_id}`.
   - Status goes `pending -> complete`. **`rejected` is final:** stop, do not deploy or configure.
   - No addresses can be created or linked before `complete`.
3. `GET /accounts/{borrower_account_id}/addresses?type=internal`. Record the internal `address_id` and its `address` (0x...).
   - It must be `status: active` (`address.ready`) and its `transfer_types` must include this chain.
4. Deploy the module: the factory owner calls `create(moduleOwner, rails)`. Verify `module.paymentRails() == rails` and `factory.isDeployedModule(module)`.
5. `POST /accounts/{borrower_account_id}/addresses/external` with an `Idempotency-Key`; scope `addresses:write`.
   - Body: `{"name":"<borrower> PaymentRails","address":"<rails>","transfer_types":["<chain>", ...]}`.
   - Record the external `address_id`. To add chains later, `PATCH .../addresses/{address_id}` with `additional_transfer_types`.
   - Brale only allows transfers to registered (whitelisted) destinations, and registering is this API call (section 12, question 3). The rails must be the **only** registered destination on this borrower's account. Never offer the borrower a UI or API to register wallets on this account. Record the account's destination list in the runbook log and check it again on every audit.
6. **Runbook check (blocking).** The `depositAddress` about to be configured must **equal** (case-insensitive hex) the internal `address` from step 3 for **this borrower's** `account_id`. The step 5 external entry's `address` must equal the rails. A second person verifies; both values go in the runbook log.
7. Write the registry row (section 3) and set its `enabled` flag for this rails. **This must happen BEFORE step 8:** once `configureToken(..., enabled=true)` runs on-chain, anyone can call `executeAction`, and the service only swaps for rails that are already registered. Running `configureToken(..., enabled=true)` first would let an early redemption go unprocessed.
8. The rails owner calls `configureToken(token, "BRALE_REDEMPTION", module, minBalance, module.encodeParams({depositAddress, usdc, minAmount}), true)`.
   - Use a non-trivial `minBalance` (spam guard: anyone can trigger `executeAction`).
   - **`minAmount`** (in input-token base units) is the minimum size of a single redemption. Set it **at or above Brale's minimum transfer amount** (runbook check, record the Brale minimum in the log). `0` is rejected. The module enforces it on-chain: a smaller `amount` returns a failed result ("Below minimum redemption") and nothing moves.
   - **`minBalance` for the token must also be at least Brale's minimum transfer amount**, so a triggered redemption can never be too small for Brale to process.

## 3. Service registry

Written only by the onboarding runbook; read-only to the hot service. One row per `(chainId, paymentRails)`:

| Field                 | Meaning                                                  |
| --------------------- | -------------------------------------------------------- |
| `account_id`          | The borrower's Brale account                             |
| `internal_address_id` | Brale id of the borrower's internal wallet               |
| `internal_address`    | 0x address of that wallet; equals the configured deposit |
| `external_address_id` | The rails, as registered under the borrower's account    |
| `module`              | The `BraleModule` for this rails                         |
| `transfer_type`       | Brale chain name for this `chainId`                      |
| `enabled`             | Kill switch                                              |

Uniqueness: `module` unique, `account_id` unique per borrower, `internal_address` unique.

**The `enabled` flag is off-chain only and does not stop on-chain redemptions.** While the token is enabled on the rails, anyone can still call `executeAction` and move the balance into the borrower's custodial wallet, and a disabled row only means the service will not swap it. So the on-chain switch always goes first when stopping, and last when starting:

- **Pause or offboard a borrower:** (1) the rails owner calls `configureToken(token, ..., enabled=false)` and waits for finality; (2) then set the registry row's `enabled` to false; (3) reconcile any deposits already in flight (section 10).
- **Resume:** (1) set the registry row's `enabled` to true; (2) then the rails owner calls `configureToken(token, ..., enabled=true)`.

## 4. Discovery and event

- Logs count only if emitted by a `module` in the registry that is also `factory.isDeployedModule` on that chain.
- Event: `RedemptionInitiated(bytes32 indexed redemptionId, address indexed token, address indexed depositAddress, uint256 nonce, uint256 amount, address paymentRails, address outputToken)`. `amount` is in the token's own base units.
- Wait for finality: use the `finalized` tag where supported, otherwise a per-chain confirmation count from config.
- Persist `redemptionId -> (txHash, logIndex, token, amount)` on first sight. If the same `redemptionId` is later seen with any different field (a reorg), refuse and alert. Never create a swap from a log that has not reached finality.
- Also require `PaymentRailsFactory.isDeployedInstance(event.paymentRails)` to be true on that chain, and keep a per-borrower kill switch (`enabled`, section 3) that is checked on every event.
- Note: the PaymentRails `ActionExecuted` event reports `amountOut == 0` for this module, always. The USDC arrives later and asynchronously through Brale, so do not use `amountOut` for accounting.

## 5. Validation

**Refuse and alert unless ALL of these hold:**

- the emitter equals `registry[chainId, event.paymentRails].module`;
- **`event.depositAddress == registry.internal_address`** for that rails' borrower account;
- the `(chainId, token)` pair is in the service's `value_type` allowlist (for example `SBC`);
- `event.outputToken` equals the configured USDC for the chain;
- the row is `enabled`.

## 6. Confirm the credit on the borrower account

- **Mandatory:** match the inbound Brale deposit on the borrower account to the on-chain tx hash (the inbound transfer's `transaction_id` must equal the log's tx hash, with matching amount and token) before creating the swap. A balance-only check is NOT sufficient, because the balance can be funded or drained by other flows.
- Polling `GET /accounts/{borrower_account_id}/addresses/{internal_address_id}/balance?transfer_type=<t>&value_type=<v>` may be used as an additional check only.
- Inbound-deposit webhooks are unconfirmed; do not depend on them.
- The balance must cover `amount`. If not, retry with backoff, then alert (the borrower has a portal login, so a borrower-initiated outflow may be possible; see questions 2 and 3 in section 12).

## 7. Amount

- `value = amount / 10^decimals(token)` as an exact decimal string with no trailing zeros. `currency = "USD"`.
- If Brale precision is coarser than the token's decimals, truncate. The dust stays in the borrower's custodial wallet and is reported.
- If the amount rounds to 0 at Brale precision (or is below Brale's minimum transfer), the service refuses to create the swap and alerts.

## 8. Create the swap transfer under the BORROWER's account

`POST https://api.brale.xyz/accounts/{borrower_account_id}/transfers` with header `Idempotency-Key: <uuid>` and body:

```json
{
  "amount": { "value": "<v>", "currency": "USD" },
  "source": {
    "address_id": "<internal_address_id>",
    "value_type": "<token value_type>",
    "transfer_type": "<t>"
  },
  "destination": {
    "address_id": "<external_address_id>",
    "value_type": "USDC",
    "transfer_type": "<t>"
  },
  "note": "cc-redemption:<0x redemptionId>"
}
```

- Build the body ONLY from event and registry data (no timestamps), so retries are byte-identical.
- On 422 `insufficient_balance`: retry later, then alert.

## 9. Idempotency-Key (UUIDv8, RFC 9562)

1. `b = redemptionId[0:16]`
2. `b[6] = (b[6] & 0x0f) | 0x80`
3. `b[8] = (b[8] & 0x3f) | 0x80`
4. Format as lowercase `8-4-4-4-12` hex.

Also keep a local unique index on `redemptionId` (Brale's key-retention window is unknown). `scripts/solidity/test/brale/BraleDryRun.s.sol` prints a reference vector. Recompute the id off-chain with `cast keccak $(cast abi-encode "f(bytes32,uint256,address,uint256)" $TYPEHASH $CHAINID $MODULE $NONCE)`, where `TYPEHASH = keccak256("BraleRedemption(uint256 chainId,address module,uint256 nonce)")`.

## 10. Lifecycle

- Track `transfer.completed` / `transfer.failed` / `transfer.refunded` (webhook HMAC `x-request-signature-sha-256`; separate testnet and mainnet subscriptions) or poll `GET /accounts/{borrower_account_id}/transfers/{id}`.
- Store `redemptionId -> (account_id, transfer.id, status)`.
- Failure means an ops alert plus manual reconciliation. The tokens sit in the borrower's custodial wallet, so no on-chain action is needed.

## 11. Key separation

| Credential      | Scopes (unconfirmed names)                                               | Held by                                          | Used for                 |
| --------------- | ------------------------------------------------------------------------ | ------------------------------------------------ | ------------------------ |
| Onboarding key  | `accounts:write`, `addresses:write` (plus reads)                         | Offline, manual only (ops vault, two-person use) | Section 2 steps 1-5 only |
| Hot service key | Transfers (create/read), balance reads, address/transfer reads, webhooks | The running service                              | Sections 5-10            |

- The hot service key never holds `accounts:write` or `addresses:write`, so a compromised service cannot create accounts or register new destination addresses. Registering an address is what whitelists it at Brale, so `addresses:write` is the key that controls where a borrower's funds can go.
- Use separate Brale Applications for testnet and mainnet. Take exact scope strings from the dashboard.

## 12. Questions for Brale (answer before mainnet)

Answers from Brale so far are recorded inline with their date. Anything without an answer is still open.

1. Can platform (Credit Coop) credentials originate transfers on managed custodial business accounts, that is `POST /accounts/{borrower_account_id}/transfers`?
   - **Answered (Brale, 2026-11-06): yes.** The service can create the swap under the borrower's account.
2. Does a platform-created managed business account give the borrower any dashboard or API login, or any ability to move funds?
   - **Partly answered (Brale, 2026-11-06):** the borrower **does get a portal login**. Brale described it as limited and recommends against borrowers using it to move funds. **Still open:** whether the portal can start transfers or off-ramps, and whether the platform can make portal access view-only or turn it off.
3. Can the platform restrict a managed account's allowed transfer destinations to its registered rails external address only?
   - **Answered (Brale, 2026-11-06):** transfers are restricted to **whitelisted destination addresses**. The whitelist is the set of external addresses registered on the account through the API (`POST .../addresses/external`). Every recipient of stablecoins from a Brale address must be pre-registered this way. Brale runs sanctions screening on each registration; any wallet that passes can be registered. Brale suggested platforms may expose a UI or API so customers can register their own wallets.
   - **Our rule:** for accounts used with `BraleModule`, **never** expose wallet registration to the borrower. Only the offline onboarding key (section 11) registers addresses, and the rails is the only registered destination. With that rule, a borrower with a portal login can move funds only back to the rails, which closes the custodial-wallet withdrawal risk (AI audit lead "offchain-custody-exit") for on-chain transfers.
   - **Still open:** whether the borrower's portal itself can register addresses, and whether off-ramps to a linked bank account (wire/ACH) also need a registered destination that only the platform can add. Until both are confirmed, treat the off-ramp path as live.
4. Is on-chain redemption, or a stablecoin swap Automation that converts deposits on arrival, on Brale's roadmap? (Asked 2026-11-06, no answer yet.)
5. What is the legal ownership and segregation of balances held in managed accounts (borrower vs platform, insolvency treatment)?
6. Is the reliance verification mode (Brale relying on Credit Coop's KYB) available, and what does it require?
7. Idempotency-Key format and retention, amount precision and swap fees, inbound-deposit detection or webhooks, and the Sepolia `transfer_type` name.
