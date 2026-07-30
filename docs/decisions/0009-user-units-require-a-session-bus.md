# 0009 — User-scope services are skipped, not failed, without a session bus

**Status:** accepted, known limitation

## Context

`systemctl --user` operations require a reachable user session bus
(normally provided by a logind session with `XDG_RUNTIME_DIR` set). Minimal
CI containers — including the one this project's own integration test runs
in — frequently have neither a logged-in session nor a lingering user
manager, even when a `services_user=` file is declared.

## Decision

`lib/roles/service.sh` probes bus reachability once
(`systemctl --user list-units`) before touching any declared user unit. If
unreachable, every declared user unit is reported as `status=skipped` with
an explanatory message, and does not count as a failure (does not produce
`EXIT_VALIDATION_ERROR` or `EXIT_APPLY_FAILED`) and does not count as
"changed" either.

## Rationale

- Treating "no session bus" as a hard failure would make `converge` fail
  on any headless/CI/first-boot context that declares user units — exactly
  the context where Archwright is most likely to run (a fresh install,
  before the user has ever logged into a graphical session).
- Treating it as silent success would be worse: an operator watching for
  "did my user units get enabled" deserves to see that they were skipped
  and why, not a clean report that hides the gap.

## Consequences

- A workspace that declares `services_user=` and runs `converge` in a
  no-session context (a CI job, a `bootstrap` script run before first
  login) will need a second `converge` run after a real session exists, to
  actually enable those units. This is a real, currently-unresolved gap in
  the end-to-end story, not just a test artifact — worth flagging to a
  workspace author in `docs/writing-a-workspace.md`.
- `examples/minimal-workspace` deliberately declares an empty
  `services_user` file specifically so the integration test exercises the
  "declared-but-empty, still valid" path without hitting this limitation
  at all — the skip path itself is not currently covered by the
  integration test. Tracked as a testing gap, see `docs/testing.md`.
