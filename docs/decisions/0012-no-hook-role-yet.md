# 0012 — No `hook` role in this release

**Status:** accepted, explicit scope cut per the implementation brief

## Context

A `hook` role — running an arbitrary command declared by the workspace,
before or after other roles — was part of the original architecture
proposal's `install/roles/` design, and is a natural, useful extension
point (a workspace author frequently needs "one weird thing" a fixed set
of roles can't express).

## Decision

Do not implement a `hook` role in this release.

## Rationale

A `hook` role means, by definition, executing content that comes from the
workspace — a directory this project explicitly treats as untrusted input
throughout the rest of the design (ADR 0007). Every other format in this
release is engineered specifically to avoid ever needing to execute
workspace-provided text; a naive `hook` role would reintroduce exactly the
risk the rest of the design avoids, and would need its own careful
scoping (what environment does it run in, what privilege, is there any
sandboxing) before it's safe to ship.

## Consequences

- Workspace authors have no escape hatch for one-off imperative steps in
  this release; anything a hook would do must currently be done manually
  or outside Archwright.
- If/when a `hook` role is designed, it should be treated as a
  security-sensitive feature requiring its own RFC and explicit
  documentation of what changes about the "never execute workspace
  content" invariant (ADR 0007) — most likely something closer to "hooks
  are opt-in per invocation, clearly logged, and never run implicitly
  during `plan` or `check`."
