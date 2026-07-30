# 0002 — check/apply/verify as the role contract

**Status:** accepted

## Context

A naive idempotency check like `pacman -Qi pkg &>/dev/null || pacman -S pkg`
only answers "is it installed", not "did the install actually work" or "is
apply ever called when nothing needs to change" — and offers no place to
report informational findings (like undeclared-but-installed packages)
separately from actionable ones.

## Decision

Every role implements three functions with fixed responsibilities:
`role_check` (read-only, compares declared vs. real), `role_apply` (the
only stage allowed to mutate the system, and only called when `check`
reported pending changes), `role_verify` (read-only, confirms `apply`
actually worked). Full contract in `docs/contract.md`.

## Rationale

- Separating "did we decide to change something" from "did the change
  work" catches a class of bugs a single check-and-fix function hides:
  `pacman -S` can exit 0 while the requested package still isn't installed
  for reasons unrelated to the command's own exit code (partial
  transaction, name mismatch after a repo change, etc.).
- Making `converge`'s orchestrator — not each role — responsible for
  "skip `apply` if `check` says we're already conformant" means every role
  gets that guarantee for free and can't accidentally skip it.
- `apply` re-deriving its own list of pending work (rather than trusting a
  value passed in from `check`) means `apply` run in isolation is still
  correct, which matters for future use cases like re-running just one
  role's apply during debugging.

## Consequences

- Every role is roughly 3x the code of a single check-and-fix function.
  Accepted: the MVP has exactly two roles, and the pattern pays for itself
  the moment a third role is added by a contributor who can copy the shape
  instead of inventing their own.
- Exit codes are a shared, small vocabulary (`docs/contract.md`) that every
  role must map its outcomes onto — a role that doesn't fit the vocabulary
  well is a signal the vocabulary needs to grow via a documented change,
  not a signal to bypass it.
