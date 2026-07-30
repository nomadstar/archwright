# Security Policy

## Reporting a vulnerability

**Please do not open a public GitHub issue for a security vulnerability.**

Use GitHub's private vulnerability reporting for this repository instead:
`Security` tab → `Report a vulnerability` (GitHub Security Advisories).
This opens a private discussion visible only to you and the maintainers
until a fix is ready, and lets us coordinate a disclosure timeline and, if
warranted, a CVE.

If you're unable to use GitHub's private reporting for some reason, open a
regular issue asking for another private channel — without describing the
vulnerability itself.

## What's in scope

- The engine (`bin/`, `lib/`) — especially anything that could make it
  `source`/`eval`/execute content from a workspace directory (a hard
  invariant of this project — see
  `docs/decisions/0007-never-execute-workspace-content.md`) or execute
  something a role shouldn't during `check`/`plan`/`drift`
  (`docs/decisions/0010-no-sandboxing-of-roles-yet.md` describes the
  current trust model).
- `scripts/check-secrets.sh` and CI configuration
  (`.github/workflows/`) — a bypass here could let real secrets slip into
  this public repository undetected.

## What's currently out of scope (by design, not oversight)

This release has no secrets handling, no AUR role, and no `hook` role —
see `docs/decisions/0008-mvp-scope-cut.md`. There is nothing to report a
vulnerability *in* for functionality that doesn't exist yet; feel free to
open a normal design discussion instead if you see a risk in how one of
those should be built later.

## Response

This is an early-stage, unfunded open-source project maintained on a
best-effort basis — there is no SLA. Reports will be acknowledged as soon
as reasonably possible.
