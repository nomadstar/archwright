# 0006 — Workspace spec version tracked separately from engine version

**Status:** accepted, mechanism not fully built yet

## Context

Once workspaces are consumed by people other than the engine's own
maintainer, breaking the on-disk format (`packages/*.txt` grammar,
`profiles/*.conf` keys, directory layout) breaks every workspace at once —
a much bigger blast radius than a bug in the engine's own code. Terraform
faces the same problem and solves it by versioning the provider protocol
independently of the CLI version.

## Decision

`ARCHWRIGHT_SPEC_VERSION` (currently `"0"`, defined in `lib/workspace.sh`)
is a separate constant from `ARCHWRIGHT_VERSION` (currently `"0.1.0-dev"`,
in `bin/archwright`). A workspace's `.archwright-version` file expresses
compatibility against the engine, and changes to the spec go through
`docs/rfcs/`, not a normal PR.

## Rationale

- It lets the engine's own code evolve (bug fixes, new roles, performance)
  on a normal release cadence without implying the on-disk format changed.
- It gives future workspace authors one number to check
  (`.archwright-version`) instead of needing to track engine releases to
  know if their workspace still parses.

## Consequences

- This release does not yet enforce a real compatibility range — `.archwright-version`
  is checked for well-formedness only (`docs/spec/workspace-layout.md`),
  not cross-checked against the running engine's declared spec version.
  Wiring that check up is deferred until the spec has had at least one
  breaking change to actually version against — enforcing compatibility
  against a spec that has never changed would be untested code with no
  real signal.
- The `docs/rfcs/` process exists (see `docs/rfcs/README.md`) but has never
  been exercised yet; its first real test will be the first proposed
  breaking change.
