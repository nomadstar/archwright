# The role contract

A **role** is a shell file at `lib/roles/<name>.sh` implementing three
functions: `role_check`, `role_apply`, `role_verify`. This document is the
authoritative reference for what each stage is allowed to do, what it must
return, and how the CLI commands use those return values. `lib/contract.sh`
and the two roles under `lib/roles/` are the reference implementation — if
they disagree with this document, that's a bug in the code, not a
correction to the rule.

## The three stages

| Stage | May have side effects? | Responsibility |
|---|---|---|
| `check` | **No.** Read-only queries against the system (`pacman -Q`, `systemctl is-enabled`, …) only. | Compare declared state to real state. Report every declared item's status. Report undeclared-but-present items as informational findings. |
| `apply` | **Yes — the only stage that may.** | Bring the system closer to the declared state for whatever `check` found pending. Must re-derive what's pending itself (it does not trust cached state from a prior `check` call). |
| `verify` | No new changes; read-only, like `check`. | Confirm, independently, that the declared items are now actually in the state `apply` was supposed to produce. |

**A stage that is not `apply` must never run a command that mutates the
system.** This is enforced by convention and code review today, not by a
sandbox — see `docs/decisions/0010-no-sandboxing-of-roles-yet.md` for why,
and what would change that.

## The rule that makes idempotency possible

> If `check` determines the system already matches the declaration, the
> orchestrator (`lib/commands/converge.sh`) must not call `apply` at all
> for that role.

This is enforced in `cmd_converge`, not inside each role: `converge` calls
`check`; only when `check` returns `EXIT_CHANGED` does it call `apply`,
followed by `verify`. A role that returns `EXIT_OK` from `check` is never
asked to `apply`. Combined with `apply` re-deriving its own work (rather
than trusting a stale plan), this is what makes a second `archwright
converge` run a no-op: the second `check` sees nothing pending, so nothing
runs.

## Exit codes

Defined once, in `lib/contract.sh`, reused by every role and every command:

| Constant | Value | Meaning |
|---|---|---|
| `EXIT_OK` | 0 | Success. For `check`/`verify`: the system already matches spec. For `apply`: nothing needed to change (should not normally happen — `converge` only calls `apply` when `check` said `EXIT_CHANGED`). |
| `EXIT_UNEXPECTED` | 1 | Internal error unrelated to workspace content — a bug, a missing binary, bad CLI arguments. |
| `EXIT_CHANGED` | 2 | Non-error. For `check`: changes are pending. For `apply`: changes were made successfully. |
| `EXIT_VALIDATION_ERROR` | 3 | The workspace, profile, or a declared item is invalid in a way that blocks this role from proceeding (see each format doc's "blocks execution" rows). |
| `EXIT_APPLY_FAILED` | 4 | `apply` attempted a change and it failed (e.g. `pacman -S` exited non-zero, or the process isn't running as root). |
| `EXIT_VERIFY_FAILED` | 5 | `apply` reported success but `verify` found the system still doesn't match spec. |

`archwright plan`, `archwright converge`, and `archwright drift` each
aggregate per-role results into one process exit code, documented in their
own doc comments in `lib/commands/*.sh`; the short version: the worst
category across all roles wins, in the order
`VALIDATION_ERROR > APPLY_FAILED > VERIFY_FAILED > CHANGED > OK`.

## Message format

Every role emits one line per item to **stdout**, via `archwright_log` in
`lib/contract.sh`:

```
[archwright] role=<role> action=<check|apply|verify> item=<name> status=<status>[ message=<quoted>]
```

`status` values in use today: `ok`, `missing`, `unresolvable`, `undeclared`,
`undeclared-foreign`, `skipped`, `installing`, `installed`, `enabled`,
`failed`, `still-missing`, `still-disabled`. This list is expected to grow;
it is not yet frozen as part of the spec (see
`docs/decisions/0011-log-status-vocabulary-is-not-frozen-yet.md`).
Warnings and internal errors go to **stderr** via `archwright_warn` /
`archwright_die`, and are never part of the machine-parseable stream —
tooling that wants to parse role output should read stdout only.

## What a role must never do

- **Never `source` or `eval` anything read from the workspace.** Package
  and unit names are data, handled with `read`/`grep`, never interpreted as
  shell.
- **Never remove a package or disable a unit**, in this release — see
  `docs/decisions/0005-no-automatic-removal.md`. `apply` only installs /
  enables.
- **Never run a `hook`-style arbitrary command from the workspace.** There
  is no `hook` role in this release — see
  `docs/decisions/0012-no-hook-role-yet.md`.
