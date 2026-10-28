# Security Policy

## Reporting a vulnerability

If you discover a vulnerability in any contract or module in this repo, **do not open a public issue**. Email **security@creditcoop.xyz** with:

- Description of the vulnerability
- Steps to reproduce or proof-of-concept
- Affected version (commit SHA, semver tag, or `deployed/...` tag if relevant)
- On-chain address(es) if you've identified affected deployments
- Your contact info for follow-up

We aim to acknowledge within 72 hours and will coordinate disclosure with you.

## Scope

**In scope:**

- Contracts in `src/core/`, `src/abstracts/`, `src/interfaces/`, `src/libraries/`
- First-party modules in `src/modules/<category>/` (excluding `contrib/`)

**Out of scope** — report directly to the module's maintainer (see `MODULES.md`):

- Community modules in `src/modules/contrib/`

**Out of scope** — report upstream:

- Issues in dependencies (OpenZeppelin, forge-std, etc.)

## Known limitations (accepted, informational)

These are by design and will not be treated as vulnerabilities unless a third party can lose funds:

- **Stray funds sent directly to a stateless module.** Modules hold nothing between calls and have no rescue function. Tokens or native value sent straight to a module address are unrecoverable; only the sender can lose them.
- **Native value moves only on the owner's say-so.** `wrapNative()` and `sweepNative()` are both owner-only, so native payments wait on the rail until the owner wraps them; the keeper then routes the wrapped balance like any other token. `sweepNative()` takes the whole wrapped balance, swap proceeds included, and an enabled wrapped route stays executable by anyone until the sweep lands; disable it in the same batch when that balance must be part of the sweep.
- **Wrapper payouts carry no `NativeReceived`.** `receive()` is silent when the sender is `wrappedNative`, so a wrapper that pays third parties (Arbitrum aeWETH `withdrawTo`) delivers value with no receipt. Balances are unaffected.
- **Zero-value native transfers revert.** Every `NativeReceived` is a real balance increase; a payer that sends zero value inside a batch sees the batch revert.
- **`previewExecution` reports pending native only when the wrapped balance is short.** Once the wrapped balance meets `minBalance`, the preview prices it alone and ignores native value that still waits for `wrapNative()`.
- **Chains whose native coin also has an ERC-20 view** (Polygon PoS `0x…1010`, Celo). Do not configure that ERC-20 address as a route: `wrapNative()` moves the same balance.
- **A new wrapper means a new factory.** `wrappedNative` is part of the CREATE2 init code, so `createDeterministic` with one salt gives different addresses on chains with different wrappers, and contracts that hold the `PaymentRailsFactory` immutably (`AtumModuleFactory`) must be redeployed to accept rails from the new one.

## Supported versions

We support the latest tagged `vX.Y.Z` release on `main`. `deployed/...` tags reference frozen commits and will not receive patches; integrators should re-deploy from the current `vX.Y.Z` line.
