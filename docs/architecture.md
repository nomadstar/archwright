# Architecture — what this release actually is

This document describes the system as implemented in this repository
today. It intentionally does not restate the full long-term vision (a
public engine consumed by many private workspaces, a pluggable secrets
provider, a community role-plugin ecosystem) — that lives in
`docs/decisions/` as the reasoning behind specific cuts, and will grow back
into a fuller architecture doc as those pieces get built. What follows is
the MVP, described precisely enough that it can be audited against the
code.

## The one property this release exists to demonstrate

> A declarative workspace can converge an Arch Linux system towards a
> desired state, and a second convergence over that same state produces no
> changes.

Everything below is in service of that, and nothing else.

## Components

```
bin/archwright              CLI entrypoint: parses args, dispatches to a command
lib/contract.sh             exit codes, logging, role dispatch — no workspace-specific logic
lib/workspace.sh            Workspace Spec v0 parser/validator — read-only, never executes workspace content
lib/commands/*.sh           validate / plan / converge / drift — orchestrate roles, own no state of their own
lib/roles/package.sh        the `package` role (pacman, official repos only)
lib/roles/service.sh        the `service` role (systemd, enable-only)
examples/minimal-workspace/ a fictional workspace: fixture + docs example + CI subject
docs/spec/                  Workspace Specification v0, format-by-format
docs/contract.md            the check/apply/verify contract, exit codes, message format
```

There is no state file, no database, no daemon. Every invocation queries
the real system fresh (`pacman -Q...`, `systemctl is-enabled`); "state" is
the system itself, not a cached record of it.

## Data flow for `archwright converge --workspace W --profile P`

```
1. bin/archwright parses --workspace/--profile, resolves W to an absolute path
2. lib/workspace.sh loads profiles/P.conf, resolving packages=/services_*= into
   absolute file paths, validating along the way (throws on any problem)
3. lib/commands/converge.sh iterates ARCHWRIGHT_ROLES = "package service", for each:
     a. call role_check  — read-only; returns EXIT_OK or EXIT_CHANGED or EXIT_VALIDATION_ERROR
     b. if EXIT_OK: skip this role, nothing to do
     c. if EXIT_CHANGED: call role_apply, then role_verify
     d. if EXIT_VALIDATION_ERROR: skip apply, remember the failure
4. aggregate the worst outcome across roles into one process exit code
```

`plan` runs only step (a) for every role. `drift` also runs only step (a),
but additionally treats any `status=undeclared*` finding as drift even
though it doesn't affect a role's own exit code (see
`lib/commands/drift.sh`).

## Why only two roles, and why these two

`package` and `service` are the two most common, least ambiguous
building blocks of "what does this system have installed and running" —
and both map onto a single, well-understood native command
(`pacman`, `systemctl`) rather than requiring the engine to shell out to a
third-party tool. `dotfiles` and `hooks` are deliberately deferred; see
`docs/decisions/0008-mvp-scope-cut.md`.

## Security posture of this release

- Nothing under a workspace directory is ever `source`d or `eval`'d — see
  `docs/decisions/0007-never-execute-workspace-content.md`.
- No role removes a package or disables a service — see
  `docs/decisions/0005-no-automatic-removal.md`.
- No secrets handling exists yet, so there is nothing to leak — the spec
  page for it (`docs/spec/secrets-provider-interface.md`) is explicitly
  marked not-implemented.
- `scripts/check-secrets.sh` scans the repository itself (not workspaces)
  for accidentally-committed personal data or credentials, and runs in CI.

## What proves the idempotency claim

`tests/integration/idempotency.sh`, run against
`examples/minimal-workspace` inside an ephemeral Arch container (see
`docs/testing.md`), executes `validate → plan → converge → converge →
drift` and asserts the **second** `converge` reports `EXIT_OK` (not
`EXIT_CHANGED`) for every role. This runs in CI on every push — the claim
is enforced, not just documented.
