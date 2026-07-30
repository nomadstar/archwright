# `assets/` — declared assets — v0.1 (additive to spec v0)

See `docs/decisions/0014-declared-assets-and-capture-restore-lifecycle.md`
for the full design and rationale. This page is the grammar reference; if
the two disagree, this page and the code are authoritative for parsing and
validation, the ADR is authoritative for *why*.

## Layout

```
<workspace>/
└── assets/
    ├── manifest/
    │   └── <id>.conf
    └── payload/
        └── <sha256[0:2]>/<sha256>
```

`assets/` is **optional** — a workspace with no `assets/` directory is
still valid. If present, `assets/manifest/` and `assets/payload/` must
both exist.

## `assets/manifest/<id>.conf`

Same `key=value` grammar as `profiles/*.conf` (`docs/spec/profiles-format.md`):
one `key=value` per line, `#` starts a comment to end of line, blank lines
ignored, no quoting.

```
# assets/manifest/wallpaper-forest.conf
dest_class=home
dest_path=Pictures/wallpapers/forest.jpg
payload_sha256=3e4f9a1b2c...  (64 lowercase hex characters)
size=482113
mode=0644
```

### `id`

The manifest's filename, minus `.conf`. Must match `^[a-z0-9][a-z0-9._-]*$`.
Stable — this is the name `archwright asset capture --id <id>` and
`archwright asset list` operate on.

### Fields

| Key | Required | Meaning |
|---|---|---|
| `dest_class` | yes | Where `dest_path` is rooted at restore time. **`home` is the only accepted value in v0.1** (meaning "relative to `$HOME`"). The field exists so a future class can be added without a manifest grammar change — see ADR 0014. |
| `dest_path` | yes | Path relative to `dest_class`'s root, e.g. `Pictures/wallpapers/forest.jpg`. Must not be absolute and must not contain a `..` path segment. |
| `payload_sha256` | yes | Lowercase hex SHA-256 of the asset's content, exactly 64 characters. Also the payload's filename (see below). |
| `size` | yes | Byte size of the payload, as a base-10 non-negative integer. |
| `mode` | yes | Octal permission bits to restore with `chmod`, 3 or 4 digits. Only the low 9 bits (owner/group/other rwx) may be set — a leading digit other than `0` (setuid/setgid/sticky) is invalid. |

There is no `captured_at` or other timestamp field: repeating a capture of
unchanged content must not modify the manifest file, and a timestamp that
updates on every run would make that impossible. See ADR 0014's
"Idempotency of `captured_at`" section.

## `assets/payload/<sha256[0:2]>/<sha256>`

The asset's raw content, named by its own SHA-256 hash (content-addressed
— the same fan-out convention git's own object store uses). The filename
is never derived from `dest_path` or any other user-controlled string: no
path-traversal-shaped input can influence where a payload file lands
inside `assets/payload/`.

## Validation

| Condition | Result |
|---|---|
| `assets/` exists but `assets/manifest/` or `assets/payload/` is missing | `EXIT_VALIDATION_ERROR` |
| A file under `assets/manifest/` is not named `<id>.conf` with `id` matching `^[a-z0-9][a-z0-9._-]*$` | `EXIT_VALIDATION_ERROR` |
| A manifest has an unknown key, a duplicate key, or a malformed (non-`key=value`) line | `EXIT_VALIDATION_ERROR` — same rule as `profiles/*.conf` |
| A manifest is missing any required key | `EXIT_VALIDATION_ERROR` |
| `dest_class` is present but not `home` | `EXIT_VALIDATION_ERROR` |
| `dest_path` is absolute, or contains a `..` segment | `EXIT_VALIDATION_ERROR` |
| `payload_sha256` doesn't match `^[0-9a-f]{64}$` | `EXIT_VALIDATION_ERROR` |
| `size` isn't a base-10 non-negative integer | `EXIT_VALIDATION_ERROR` |
| `mode` doesn't match a plain 3-4 digit octal value, or sets setuid/setgid/sticky | `EXIT_VALIDATION_ERROR` |
| No payload file exists at `assets/payload/<sha256[0:2]>/<sha256>` for a manifest's `payload_sha256` | `EXIT_VALIDATION_ERROR` — reported as a missing payload |
| The payload file's actual SHA-256 doesn't match its own filename | `EXIT_VALIDATION_ERROR` — reported as a corrupted payload |
| Two manifests declare the same `dest_class`+`dest_path` | `EXIT_VALIDATION_ERROR` — ambiguous restore target |

`archwright validate` checks every manifest under `assets/manifest/*.conf`
the same way it checks every `profiles/*.conf` file, independent of which
profile (if any) is passed to `--profile`.
