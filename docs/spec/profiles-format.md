# `profiles/*.conf` format — v0

A flat `key=value` file, one profile per file, named `profiles/<profile-name>.conf`
— `<profile-name>` is exactly what you pass to `--profile` on the CLI.

```
# profiles/ci.conf
name=ci
description=Minimal profile used by CI and the getting-started guide
packages=packages/official.txt
services_system=services/system.txt
services_user=services/user.txt
```

This format was chosen over YAML/TOML specifically so it can be parsed
without a library and without ever needing to `source` the file — see
`docs/decisions/0003-plain-text-formats-over-yaml-toml.md`. It is
intentionally not a general-purpose format: it has exactly the fields below
and nothing else.

## Grammar

- One `key=value` pair per line.
- `#` starts a comment to end of line; blank lines are ignored.
- Whitespace around the key is trimmed; the value is taken verbatim after
  the first `=` (so values cannot themselves contain unescaped `#`, and
  there is no quoting mechanism in v0).
- Multiple file references in one value are comma-separated, e.g.
  `packages=packages/official.txt,packages/extra.txt`. Each path is
  resolved relative to the workspace root.

## Fields

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | Free-text profile name (conventionally matches the filename). |
| `description` | no | Free-text, shown in `plan`/`converge` output. |
| `packages` | yes | Comma-separated list of files following `packages-format.md`. |
| `services_system` | no | Comma-separated list of files following `services-format.md`, managed as system units. |
| `services_user` | no | Same, managed as user units (`systemctl --user`). |

## Validation — what blocks execution

| Condition | Result |
|---|---|
| Unknown key (anything not in the table above) | `EXIT_VALIDATION_ERROR` — the whole profile fails to load. |
| A key appears twice in the same file | `EXIT_VALIDATION_ERROR` — v0 does not define "last wins"; a duplicate key is always a hard error, on the theory that a silently-overridden line is a worse failure mode than refusing to guess. |
| `name` or `packages` missing | `EXIT_VALIDATION_ERROR` — these are the only two required keys. |
| A line is not valid `key=value` (no `=` at all) | `EXIT_VALIDATION_ERROR`. |
| A file referenced by `packages=`, `services_system=`, or `services_user=` does not exist on disk | `EXIT_VALIDATION_ERROR`, reported with the missing path. |
| `services_system` / `services_user` omitted entirely | **Not an error** — treated as an empty list; the service role has nothing to do for that scope. |

`archwright validate` (unlike `plan`/`converge`/`drift`) checks **every**
profile in `profiles/*.conf` this way, even ones not passed via `--profile`,
so a broken profile is caught before someone tries to use it.
