# 0006 — Workspace spec version tracked separately from engine version

**Status:** accepted, mechanism not fully built yet; amended (see below)

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
compatibility against the **workspace spec version**, not the engine
version — a workspace author never needs to know which engine release
they're running against, only which spec their workspace was written for.
Changes to the spec that break existing, valid workspaces go through
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

## Amendment — explicit major/minor/doc-only policy

**Added when:** ADR 0014 (declared assets) — the first real change to the
workspace spec since this ADR was written — made it clear that "additive
and compatible" is still a semantic change to the format, not a non-event,
and deserved its own numbering policy rather than being left as an
unstated assumption.

`ARCHWRIGHT_SPEC_VERSION` is a `major.minor` pair (e.g. `0.1`, not a bare
`0`):

| Change type | Version effect | Process |
|---|---|---|
| Additive, compatible (a new optional directory, a new optional key, a new role that doesn't require existing workspaces to change) | Minor increment | Normal PR + ADR (`docs/decisions/`) |
| Incompatible (removes/renames a required file, changes the meaning of an existing key, tightens validation such that a previously-valid workspace becomes invalid) | Major increment | RFC (`docs/rfcs/`), with a mandatory migration section |
| Purely documentational (wording, examples, typos — no behavior change) | No increment | Normal PR, ADR optional |

**ADR 0014 is the first concrete example of the first row**: `assets/` is
a new, optional top-level directory. Every workspace valid under the spec
before ADR 0014 is still valid after it — nothing about
`packages/`, `services/`, or `profiles/*.conf` changes, and a workspace
that never adds an `assets/` directory is unaffected. That makes it a
minor increment, not a major one, and it goes through a normal PR with an
ADR, exactly as this table prescribes — not through `docs/rfcs/`.

While the spec remains marked experimental (v0, per
`docs/spec/README.md` and `docs/spec/workspace-layout.md`), the major
component may stay at `0` indefinitely — a `0.x` spec communicates "no
compatibility promise yet" the same way `ARCHWRIGHT_VERSION`'s
`0.1.0-dev` does for the engine. Moving to `1.0` is itself a decision
this ADR does not make; it belongs to whichever future ADR or RFC first
declares the spec stable.

**This amendment documents the policy only.** It does not change the
Consequences section above: `.archwright-version` is still checked for
well-formedness only, not cross-checked against
`ARCHWRIGHT_SPEC_VERSION` at runtime. Real range enforcement remains
deferred until there's been an actual major (breaking) change to enforce
a range against — a minor bump from ADR 0014 does not, by itself, meet
that bar.
