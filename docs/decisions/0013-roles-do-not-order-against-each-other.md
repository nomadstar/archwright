# 0013 — Roles don't know about each other's pending changes

**Status:** accepted, known limitation (found via CI, not by design review)

## Context

`examples/minimal-workspace` originally declared `openssh` (a package) and
`sshd.service` (the unit that package ships) in the same profile. This
looked like a natural, realistic pairing. The integration test
(`tests/integration/idempotency.sh`) caught that `archwright plan` on a
fresh container reported `EXIT_VALIDATION_ERROR` instead of the expected
`EXIT_CHANGED`: the `service` role's `check()` looked for `sshd.service`'s
unit file before the `package` role had installed `openssh`, found
nothing (`systemctl list-unit-files` came up empty), and correctly — by
its own local logic — reported `status=unresolvable`.

The underlying cause: `plan` runs `check()` for every role, in order, but
never runs `apply()` for any of them (`docs/contract.md`). `converge`
*does* run package's `apply()` before service's `check()` in the same
invocation (`ARCHWRIGHT_ROLES="package service"` in
`lib/commands/_common.sh`), so this specific pairing would actually have
worked under `converge` — just not under `plan`, and not under `service`
role's `check()` considered on its own.

## Decision

Do not build cross-role dependency resolution (a role declaring "I
provide unit files that role X needs to see") in this release. Instead:
document the limitation, and choose the bundled example so it doesn't hit
it — `examples/minimal-workspace` declares `systemd-timesyncd.service`
(shipped by `systemd`, present on every Arch system independent of what
`packages/*.txt` declares) instead of pairing a package with its own
service.

## Rationale

- Solving this generally means either (a) roles declaring outputs/inputs
  to each other and the orchestrator topologically sorting `check()` calls
  around hypothetical future state, or (b) `plan` simulating `apply()`
  without truly applying it (a real "dry run" mode distinct from
  "check-only"). Both are real design projects, not a quick fix, and nothing
  in the MVP's brief asked for cross-role dependency modeling.
- A workspace author hitting this in practice has an easy, correct
  workaround: run `archwright converge` directly (which already handles
  this pairing correctly via role ordering) instead of relying on `plan`
  to preview it first, or accept that `plan` may report a false
  `EXIT_VALIDATION_ERROR` for a service whose providing package isn't
  installed yet — that's imprecise, not unsafe (no apply happens during
  `plan` regardless).

## Consequences

- `plan` and `check()` in isolation are more conservative than
  `converge`: a workspace can be entirely correct and still have `plan`
  report a validation error for a not-yet-installed service if the
  workspace author pairs a package with the service it provides.
  `docs/spec/services-format.md`'s "blocks execution" row for
  `status=unresolvable` doesn't currently caveat this — worth revisiting
  if it causes real confusion once workspaces beyond the bundled example
  exist.
- If a future workspace genuinely needs to pair "install this package"
  with "enable the service it ships" in one profile, splitting it across
  two `converge` runs (first without the service declared, then with it)
  is the current workaround; a real fix belongs in a future RFC once this
  proves to matter beyond the one example that already hit it.
