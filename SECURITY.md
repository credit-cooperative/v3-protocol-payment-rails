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
- **Native value is held, not routed.** `receive()` accepts native value and only emits `NativeReceived`. Nothing wraps, swaps or forwards it; it stays on the rail until the owner calls `sweepNative(recipient)`, which sends the whole native balance in one call. ERC-20 balances are never part of the sweep.
- **A new PaymentRails bytecode means a new factory.** `PaymentRailsFactory` deploys the PaymentRails creation code it was compiled with, so rails that accept native value come only from a factory built from this version. Contracts that hold the `PaymentRailsFactory` address immutably (`AtumModuleFactory`) must be redeployed to accept rails from the new one.

## Supported versions

We support the latest tagged `vX.Y.Z` release on `main`. `deployed/...` tags reference frozen commits and will not receive patches; integrators should re-deploy from the current `vX.Y.Z` line.
