# 0003 — Plain-text list + flat key=value instead of YAML/TOML

**Status:** accepted (v0, revisit once spec stabilizes)

## Context

The workspace needs to declare lists (packages, services) and small
structured records (profiles). YAML and TOML are the obvious formats and
were the ones proposed in the original architecture discussion. Both
require either a parsing library (a new dependency, and one more thing a
contributor needs installed to hack on the engine) or a hand-rolled parser
covering a meaningful subset of a real spec (nesting, quoting, escaping,
anchors for YAML) — which is where most home-grown config parsers
accumulate bugs.

## Decision

`packages/*.txt` and `services/*.txt` are flat line-lists (`#` comments,
one entry per line). `profiles/*.conf` is a flat `key=value` format with a
fixed, small set of allowed keys — not a general-purpose serialization
format. Full grammars in `docs/spec/`.

## Rationale

- Both formats are simple enough to specify completely, in prose, in about
  one page each — see `docs/spec/packages-format.md`,
  `docs/spec/profiles-format.md`.
- Both are parseable with `read`/`grep`/string manipulation in bash, with
  no risk of the parser itself needing to `eval` or `source` anything (a
  hard security requirement — ADR 0007). A YAML parser correct enough to
  handle nested structures safely in pure bash would be a project of its
  own.
- Zero new dependency for someone who just wants to try `archwright
  validate` against their own workspace.

## Consequences

- The format cannot express nesting. If a future need arises (e.g. a role
  needing structured per-item options, not just a name), this decision
  will need revisiting — most likely by introducing YAML for the specific
  file that needs it, once there's a real dependency budget for a parser
  (`yq` becoming a documented prerequisite, for instance), rather than by
  smuggling structure into the flat formats.
- Because the spec is explicitly v0/unstable, this is not a promise the
  format never changes — it's a promise that a change goes through
  `docs/rfcs/` once real workspaces exist to break.
