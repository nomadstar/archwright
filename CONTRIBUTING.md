# Contributing

Thanks for considering it — this project is early (v0.1.0-dev) and the
process below is itself a first draft, expected to change as real
contributions arrive.

## Before you start

Read `docs/architecture.md` and `docs/contract.md` first. Almost every
non-obvious design choice already has an ADR in `docs/decisions/` — if
you're about to propose something that looks like it contradicts one,
check there first; either it explains why, or it's out of date and worth
challenging directly.

## Two different kinds of change

**Code that doesn't change the Workspace Specification** (a bug fix, a
faster parser, a new CLI flag, a new role) — open a normal pull request.
Include an ADR in `docs/decisions/` if the change involved a non-obvious
trade-off; skip it for straightforward fixes.

**A change to `docs/spec/`** that would break an existing, valid
workspace — a new required field, a stricter validation rule, a changed
file format — goes through the RFC process in `docs/rfcs/` first. See
`docs/rfcs/README.md`.

## Adding a role

A role is a strong extension point by design (see
`docs/decisions/0010-no-sandboxing-of-roles-yet.md` for the current trust
model — roles are framework code, reviewed like any other PR, not
sandboxed workspace plugins yet). A new role must:

- implement `role_check`, `role_apply`, `role_verify` per `docs/contract.md`;
- never `source` or `eval` anything read from a workspace
  (`docs/decisions/0007-never-execute-workspace-content.md`);
- never remove/disable something the declaration doesn't ask for
  (`docs/decisions/0005-no-automatic-removal.md`);
- come with unit test fixtures and be exercised by
  `tests/integration/idempotency.sh` (extend `examples/minimal-workspace`
  if the new role needs something declared to check against).

## Running the tests locally

See `docs/testing.md`. Unit tests need `bats` and touch nothing on your
system; the integration test needs a container and does mutate its
(disposable) package/service state — never run it outside a container.

## Code style

Bash, `set -euo pipefail` only in entrypoints (see the note at the top of
`lib/contract.sh` for why library files don't set shell options
themselves). Run `shellcheck` before opening a PR — CI does too.

## Commit messages

Small, conceptually separate commits over one large one. Explain *why*, not
just *what* — the diff already shows what changed.
