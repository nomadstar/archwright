# 0010 — Roles are trusted framework code, not sandboxed

**Status:** accepted, known limitation

## Context

`lib/roles/*.sh` are shipped by the framework itself (not by a workspace),
so the "never execute workspace content" invariant (ADR 0007) already
keeps workspace-authored code out of the execution path. But nothing in
`archwright_run_role` (`lib/contract.sh`) technically stops a role's
`role_apply` from running a command outside its documented scope — the
`check`-must-have-no-side-effects rule is a documented convention enforced
by code review, not by a runtime restriction (e.g. a restricted shell,
seccomp, or a read-only filesystem view during `check`).

## Decision

Ship without sandboxing in this release. Rely on: (1) only two roles exist,
both authored and reviewed as part of this repository; (2) the contract is
documented precisely enough (`docs/contract.md`) that a reviewer can check
a role's `role_check` for side effects by reading it; (3) CI's idempotency
test (`tests/integration/idempotency.sh`) would catch a `check` that
secretly mutates state, because a mutating `check` would itself change
what the *second* `check` sees.

## Rationale

Building a real sandbox (namespaces, seccomp filters, or even just
`chroot`-ing `check` into a read-only view) is a substantial project on its
own, and premature while there are only two, fully-reviewed, framework-
authored roles. The risk this protects against — a buggy or malicious role
— only becomes acute once third-party roles are accepted from the
community (the extensibility goal described in the broader architecture
proposal).

## Consequences

- This is the primary thing that must change before a community role-
  plugin system (accepting `lib/roles/*.sh`-shaped contributions from
  people other than the core maintainers) ships — see the corresponding
  gap noted for future governance work.
- Until then, `check`/`apply`/`verify` correctness for the two built-in
  roles is a code-review and testing problem, not a runtime-enforced one.
