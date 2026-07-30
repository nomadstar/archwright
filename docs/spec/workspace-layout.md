# Workspace layout — v0

## Required

```
<workspace>/
├── .archwright-version
├── profiles/
│   └── <name>.conf        (at least one)
├── packages/
│   └── *.txt               (referenced by at least one profile)
└── services/
    └── *.txt               (referenced by at least one profile, may be empty files)
```

`archwright validate --workspace <path>` fails with `EXIT_VALIDATION_ERROR`
(3) if `profiles/`, `packages/`, or `services/` is missing, or if
`profiles/` contains zero `*.conf` files.

## `.archwright-version`

A single line matching `^[0-9]+(\.[0-9]+){0,2}$`, optionally prefixed with
`^` (meaning "compatible with this minor version or newer, same major" —
the same convention as a caret range, though v0 of the engine does not yet
enforce ranges; it only checks the file is present and well-formed). Example:

```
^0.1
```

**Blocks execution if:** the file is missing, empty, or does not match the
pattern above.

## Optional

```
<workspace>/
└── assets/
    ├── manifest/
    │   └── *.conf
    └── payload/
        └── <sha256[0:2]>/<sha256>
```

`assets/` is optional — see `docs/spec/assets-format.md` for the grammar.
Added in spec `0.1` (ADR 0014); a spec-`0.0`-shaped workspace without
`assets/` remains valid, per the additive/compatible policy in
`docs/decisions/0006-spec-versioned-separately-from-engine.md`.

## What is *not* part of the layout yet

`dotfiles/`, `secrets/`, `bootstrap/hardware/`, and a `hooks` role are all
deliberately absent from v0 — see `docs/decisions/0008-mvp-scope-cut.md`
for what was cut and why. A workspace may contain other files and
directories the engine ignores; validation only checks for the required
ones, it does not reject unknown top-level content.
