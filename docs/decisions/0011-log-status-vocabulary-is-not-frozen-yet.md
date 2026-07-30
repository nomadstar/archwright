# 0011 — The `status=` vocabulary in log lines is not a frozen part of the spec

**Status:** accepted

## Context

`docs/contract.md` lists the `status=` values the two built-in roles emit
today (`ok`, `missing`, `unresolvable`, `undeclared`, `undeclared-foreign`,
`skipped`, `installing`, `installed`, `enabled`, `failed`, `still-missing`,
`still-disabled`). Nothing currently parses this output downstream — it's
for a human reading `converge` output, plus `drift`'s own
`grep -q 'status=undeclared'` on the captured text.

## Decision

Treat the exit codes (`docs/contract.md`'s table) as the stable, contractual
signal a role gives the orchestrator, and the specific `status=` strings as
documentation of current behavior, not a frozen enum. A future role — or a
future version of `package`/`service` — can introduce a new `status=` value
without that being a breaking spec change, as long as the exit-code
contract is unchanged.

## Rationale

Freezing the exact set of status strings now, before any external tooling
consumes them, would lock in vocabulary chosen for two roles' worth of
use cases. The exit codes are the part other code (the CLI's aggregation
logic, `drift`'s error/no-error decision) actually depends on structurally;
the strings are for a human, and humans tolerate a growing vocabulary
better than a breaking machine format.

## Consequences

- `lib/commands/drift.sh` currently does a substring `grep` for
  `status=undeclared` rather than an exact `status=` enum check — a
  reasonable trade while the vocabulary is fluid, revisit if it starts
  false-matching a future status string.
- If a real machine consumer of this output shows up (a dashboard, a
  linter), that's the trigger to write an RFC freezing the vocabulary —
  not something to do speculatively now.
