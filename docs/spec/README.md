# Workspace Specification

**Status: v0 — experimental and unstable.** Anything in this directory may
change or break in an incompatible way without a deprecation period while
the spec is at v0. Once real workspaces depend on it, changes go through
the RFC process in `docs/rfcs/` instead (see
`docs/decisions/0006-spec-versioned-separately-from-engine.md`).

A **workspace** is a directory — normally a private Git repository — that
declares the desired state of an Arch Linux system in the format described
by these documents. Archwright (the engine) reads a workspace; it never
ships with one.

## Documents

| File | Defines |
|---|---|
| [`workspace-layout.md`](workspace-layout.md) | Required files/directories and `.archwright-version` |
| [`packages-format.md`](packages-format.md) | The plain-list format used by `packages/*.txt` |
| [`services-format.md`](services-format.md) | The plain-list format used by `services/*.txt` |
| [`profiles-format.md`](profiles-format.md) | The `profiles/*.conf` key=value format and how a profile selects package/service files |
| [`secrets-provider-interface.md`](secrets-provider-interface.md) | The abstract contract a secrets provider must implement — **not yet implemented**, documented here only so the shape is settled before code is written against it |

## Design principles behind v0

- **No format requires executing anything.** Every file the engine reads
  from a workspace is parsed with `read`/`grep`-style line processing.
  Nothing under a workspace is ever `source`d or `eval`'d. This is a
  security invariant, not a style preference — see
  `docs/decisions/0007-never-execute-workspace-content.md`.
- **Plain text over a DSL.** v0 deliberately avoids YAML/TOML parsers and
  their edge cases in favor of two formats simple enough to describe
  completely in one page each: a line list and a flat key=value file. See
  `docs/decisions/0003-plain-text-formats-over-yaml-toml.md`.
- **Every error is either "blocks execution" or "informational."** The spec
  documents, for every rule, which bucket it falls into — see the
  "Validation" section of each format document.
