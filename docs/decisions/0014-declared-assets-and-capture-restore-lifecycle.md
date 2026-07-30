# 0014 — Declared assets: capture/restore lifecycle

**Status:** proposed, pending implementation

## Context

A workspace today can declare packages and services, but a real
configuration frequently depends on files that are neither: an i3 config
references a wallpaper under `~/Pictures/`, a status bar script lives
under `~/.local/bin/`. Without a way to declare these, a workspace is not
actually reproducible — it converges the parts native Arch tooling already
understands and silently drops the rest, which is exactly the "knowledge
trapped on one machine" failure this project's manifesto exists to close.

`dotfiles` was deferred in ADR 0008 as "a design question, not a small
addition." This ADR resolves a narrower, more tractable slice of that
question: not dotfile *management* (symlink orchestration, templating —
still deferred, still a candidate for delegating to chezmoi in a future
ADR), but declaring and reproducing individual **asset files** a
configuration depends on. This was designed across several rounds of
review; the version below reflects three corrected drafts, not the first
proposal.

## Decision

### Three directions, three verbs

Every operation in this ADR moves data in exactly one direction, and the
command name says which:

| Direction | Command | Mutates |
|---|---|---|
| system → workspace | `archwright asset capture <path>` | workspace (local) |
| workspace → system | `archwright converge` (the `assets` role) | system (local) |
| (read-only, either side) | `archwright asset scan <file...>` / `archwright asset list` | nothing |

`capture` was chosen over the previously-proposed `include` specifically
because `include` reads as a declarative reference, while the operation
copies bytes — the verb has to admit that.

### Workspace layout — manifest and payload are separate namespaces

```
<workspace>/
└── assets/
    ├── manifest/
    │   ├── wallpaper-forest.conf
    │   └── brightness-script.conf
    └── payload/
        ├── 3e/3e4f9a...c1
        └── 9a/9a12bc...07
```

`assets/manifest/<id>.conf` uses the exact `key=value` grammar
`profiles/*.conf` already uses (same parser in `lib/workspace.sh`, no new
file format):

```
dest_class=home
dest_path=Pictures/wallpapers/forest.jpg
payload_sha256=3e4f9a...c1
size=482113
mode=0644
```

`assets/payload/<sha256>` stores the actual bytes, named by content hash
(fan-out into a two-character prefix directory, the same convention git's
own object store uses), never by the destination path. This is a
deliberate decoupling, not an implementation detail:

- The payload filename is never derived from user-controlled path data —
  there is no `dest_path` substring anywhere in `assets/payload/`, which
  removes path-traversal as a category of bug in the store itself.
- Two assets with identical content (two profiles capturing the same
  wallpaper) share one payload file for free.
- `dest_class=home` is the only value v1 accepts (meaning "relative to
  `$HOME`"), but the field exists precisely so a future `xdg_config`,
  `system`, or similar class doesn't require changing the manifest
  grammar — the manifest was designed to survive that extension without a
  breaking change.

### `id`

The manifest filename stem. A slug matching `^[a-z0-9][a-z0-9._-]*$`,
either passed explicitly (`--id`) or derived from a sanitized `dest_path`.
If a derived or explicit `id` already names a manifest whose `dest_path`
differs from the one being captured, `capture` aborts rather than
silently picking a numbered suffix — id collisions are for a human to
resolve, not for the tool to paper over.

## Command semantics

### `archwright asset capture <path> [--id <slug>] [--allow-executable] [--max-size <bytes>] --workspace <dir>`

Pipeline, each step a hard gate unless noted:

1. `<path>` exists and is a **regular file** — not a symlink, not a
   socket/device/FIFO. No override.
2. `realpath(<path>)` resolves to somewhere inside `$HOME` (the only
   permitted root in v1). A symlink as the input path is rejected
   outright, not followed — v1 does not resolve through symlinks and
   silently capture whatever they point at. No override.
3. Hard denylist, checked against the resolved path: anything under
   `~/.ssh` or `~/.gnupg`; filenames matching `.env*`, `*.pem`, `*.key`,
   `id_rsa*`, `*.p12`, `*.pfx`, `*.crt`, or any `*_history` shell history
   file. **No override exists for this step, under any flag, ever.**
4. Size ≤ a default limit, overridable narrowly with `--max-size`. No
   generic bypass — this is the only size-related knob.
5. Permission bits: `mode = stat(path).mode & 0777` (see "Permission
   semantics" below). If any executable bit is set, `capture` requires
   `--allow-executable`; without it, abort. This is a named, narrow
   override — unlike step 3, an executable *is* a legitimate asset (a
   status-bar script), so this gate can be satisfied deliberately.
6. Hash the source file (`sha256`), pre-copy.
7. Copy the source into a uniquely-named temporary file under
   `assets/payload/`.
8. Re-stat and re-hash the **source** (not the copy), post-copy. If it no
   longer matches step 6's hash, the file changed during capture
   (TOCTOU): abort, discard the temporary payload, ask the user to retry.
9. If a payload already exists under that hash, discard the temporary
   file (dedup — this is also the case a second, unchanged `capture`
   takes). Otherwise, rename the temporary file to its final
   content-addressed name.
10. Compute the manifest content (`dest_class`, `dest_path`,
    `payload_sha256`, `size`, `mode`).
11. If `assets/manifest/<id>.conf` does not exist: write it.
    If it exists and its content is byte-for-byte identical to what was
    just computed: **do not touch the file** — not even its mtime.
    If it exists and differs: overwrite it.

### Idempotency of `captured_at` — resolved by removing it

An earlier draft included a `captured_at` timestamp in the manifest. That
field cannot exist without becoming a permanent exception to
idempotency — capturing unchanged content on Tuesday and again on Friday
would touch the manifest file both times, for no functional reason,
purely because the timestamp differs. `captured_at` is dropped from the
v1 manifest grammar entirely. If provenance/audit history is ever needed,
it belongs in an append-only capture log outside the manifest (so the
declarative, idempotent artifact and the historical record don't share a
file) — not designed here, not needed by anything in this release.

### Exit codes (reusing `lib/contract.sh`'s constants, not a parallel scheme)

`capture`:

| Code | Meaning |
|---|---|
| `EXIT_OK` (0) | Manifest already matched computed content exactly; nothing was written. |
| `EXIT_CHANGED` (2) | A manifest was created or updated. |
| `EXIT_VALIDATION_ERROR` (3) | Any hard gate failed (steps 1–5, or the TOCTOU check in step 8). |
| `EXIT_UNEXPECTED` (1) | Operational failure unrelated to the gates — I/O error, disk full, permission denied reading the source. |

`scan`:

| Code | Meaning |
|---|---|
| `EXIT_OK` (0) | The scan completed. This is returned **whether or not any candidates were found** — an empty or all-`missing` result is not a failure. |
| `EXIT_VALIDATION_ERROR` (3) | `--workspace` points at an invalid workspace, or an existing manifest file under it fails to parse (corrupt). |
| `EXIT_UNEXPECTED` (1) | The input file/directory passed to `scan` doesn't exist, or can't be read (permissions). |

This corrects an earlier draft that returned `0` unconditionally — a
report-only command should still fail loudly on operational errors; only
the *content* of a successful scan (candidates, dangling references,
unparsed lines) is exempt from being treated as failure.

`list`: `EXIT_OK` if the workspace and every manifest under it parse
cleanly; `EXIT_VALIDATION_ERROR` otherwise.

### `archwright asset scan <file-or-dir...> --workspace <dir>`

Never runs implicitly over all of `$HOME` — it only inspects the paths
given to it explicitly. For each absolute-path-shaped reference it finds
inside those inputs, it reports exactly one of:

| Status | Meaning |
|---|---|
| `referenced` | Path found in input, exists on disk, not yet declared in any manifest. |
| `declared` | Path found in input, already matches some manifest's `dest_path`. |
| `missing` | Path found in input, does not exist on disk. |
| `unparsed` | Something path-shaped was found but couldn't be resolved with confidence (a shell variable, a glob, a relative path with no clear base). |

There is no "ignored" or "irrelevant" status. `scan` never makes a
relevance judgment — it reports facts, the user decides. This is
heuristic (plain-text pattern matching, not a per-application config
parser) and is documented as such: it can produce both false positives
and false negatives, and its output is a list of candidates, never a
claim of completeness.

### `archwright converge` — the `assets` role

Fits the existing role contract (`docs/contract.md`) exactly, no changes
to that document:

| Stage | Behavior |
|---|---|
| `check` | For each declared asset, hash the real file at `$HOME/<dest_path>` (if present) and compare against `payload_sha256`. Report `ok` / `missing` / `modified`. |
| `apply` | Only for items `check` found pending: copy the payload to `$HOME/<dest_path>`, then `chmod` it explicitly to the manifest's `mode` — restoring exactly the masked bits recorded at capture time, nothing more. |
| `verify` | Re-hash the real file, confirm it matches `payload_sha256` and that its mode matches. |

Same exit codes, same log line format (`role=assets action=... item=...
status=...`) as `package`/`service`. This is the one part of this ADR
that participates in the check/apply/verify contract; `capture`/`scan`/
`list` deliberately do not, because they aren't converging toward a
declared state — they're producing or inspecting the declaration itself.

## Permission semantics

- Captured mode = `stat(source).st_mode & 0777` — only the nine
  user/group/other rwx bits. `setuid`, `setgid`, and the sticky bit are
  masked out unconditionally, with no flag that restores them. There is
  no legitimate case among wallpapers, scripts, fonts, or icons that needs
  any of the three.
- ACLs, Linux capabilities, and extended attributes are **not** captured
  and **not** restored. `capture` uses a plain file copy; nothing invokes
  `getfacl`/`setfacl`, capability tooling, or `xattr` handling. This is a
  known, documented limitation — a source file whose access control
  depends on an ACL will restore with only its base rwx bits.
- Restore (`assets` role `apply`) sets the mode with an explicit `chmod`
  call using the manifest's recorded value — it does not rely on the copy
  operation's default mode (typically governed by `umask`, which archived
  correctness must not depend on).
- If a file was accepted at capture time via `--allow-executable`, its
  execute bits are already part of the masked `mode` value stored in the
  manifest — restore requires no special case for "this one was
  executable," it simply `chmod`s the same recorded value it always does.

## Failure and recovery behavior

- A crash between steps 7 and 9 of `capture` (temp file written, not yet
  renamed) leaves a stray temporary file under `assets/payload/`. It is
  not referenced by any manifest and is inert. v1 does not garbage-collect
  it automatically — automatic deletion of anything is out of scope by
  the project's own invariant against destroying information; a future
  `asset gc` command is a plausible extension, not built here.
- A crash after step 9 but before step 11 (payload committed, manifest
  not yet written) is safe to simply re-run: step 9 finds the payload
  already present under its hash (dedup path) and step 11 proceeds
  normally.
- `converge`'s `assets` role failure modes are already covered by the
  existing contract: `EXIT_APPLY_FAILED` if the copy/chmod fails,
  `EXIT_VERIFY_FAILED` if `apply` reported success but the post-hash
  doesn't match.

## Security consequences

- The hard denylist (SSH/GPG directories, key/secret-shaped filenames,
  shell history) exists specifically so that a moment of carelessness at
  `capture` time — not a malicious workspace, a human running the wrong
  command — cannot put credential material into a workspace that a future
  `publish` (ADR 0015) might then push to a remote. This is a capture-time
  control, independent of and in addition to whatever secret scanning
  `publish` runs later.
- `realpath` containment plus refusing symlinked inputs closes the two
  most direct ways a capture could be pointed, accidentally or not, at a
  file outside `$HOME`.
- There is deliberately no single flag that disables every protection at
  once. `--max-size` and `--allow-executable` are the only overrides that
  exist, and each defeats exactly one, named, non-security-critical gate.
  Nothing overrides the denylist, the regular-file check, or the
  containment check.
- Content-addressed payload storage means the store itself has no
  path-derived filenames to sanitize — see "Workspace layout" above.

## Compatibility with existing ADRs

| ADR | Relationship |
|---|---|
| 0002 (check/apply/verify contract) | The `assets` role in `converge` fully conforms, unchanged. `capture`/`scan`/`list` are intentionally outside this contract — they don't converge toward a declared state, they produce or inspect it. |
| 0003 (plain text over YAML/TOML) | Manifest reuses the existing `key=value` grammar and parser; no new format introduced. |
| 0005 (no automatic removal) | `assets` role `apply` only ever creates/overwrites at the destination; it never deletes a file from `$HOME`, declared or not. |
| 0006 (spec versioned separately) | See ADR 0006's amended policy, cross-referenced below — `assets/` is an additive, minor-version change. |
| 0007 (never `source`/`eval` workspace content) | Manifests are parsed with the same safe line-based parser as `profiles/*.conf`. Payload files are only ever `cp`'d and `chmod`'d, never executed, regardless of their own executable bit. |
| 0008 (MVP scope cut) | This ADR resolves the `assets`-shaped slice of the deferred `dotfiles` question; symlink/templating management (the chezmoi-or-reimplement decision) remains deferred. |

## Consequences

- A workspace can now express "this configuration also needs this
  wallpaper/script/font," and `converge` reproduces it on a new machine
  with the same idempotency guarantee already proven for `package` and
  `service`.
- Capturing is still manual and per-file by design — there is no
  "capture everything referenced" bulk operation. This is intentional
  friction: every asset in a workspace is there because a human looked at
  it and said yes.
- The `dotfiles` role itself (symlink management, templating) is still
  not designed. This ADR does not close ADR 0008's deferred item, only a
  piece of it that doesn't require deciding chezmoi-vs-reimplement first.

## Scope explicitly deferred

- Any `dest_class` other than `home`.
- Capturing directories (only individual regular files in v1).
- Following symlinks at capture time.
- ACL, Linux capability, and extended-attribute capture/restore.
- A `capture --force` or any single flag disabling multiple protections
  at once.
- Filename/path-based "this looks private" heuristics (e.g. flagging
  `Documents/`, `thesis`, financial-sounding names) — only structural,
  verifiable checks exist in v1; guessing at semantic privacy is exactly
  the kind of inference this design was corrected to avoid.
- A garbage-collection command for orphaned temporary/payload files.
- Any interaction with a remote — that is the entirety of ADR 0015, and
  this ADR is designed to be implementable and testable without it.
