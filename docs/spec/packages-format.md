# `packages/*.txt` format — v0

A plain list, one official-repo package name per line.

```
# comments start with # and run to end of line
tree
openssh
```

## Grammar

- One package name per line.
- Everything from `#` to end of line is a comment (a `#` need not be at the
  start of the line; `tree # for the fs role docs example` is valid and the
  package name is `tree`).
- Leading/trailing whitespace is trimmed.
- Blank lines (after comment-stripping) are ignored.
- No quoting, no escaping, no continuation lines.

## Combination across files

A profile may reference more than one packages file
(`packages=packages/official.txt,packages/desktop.txt`). The engine reads
them in the order listed and unions the result.

## Validation

| Condition | Bucket |
|---|---|
| Same package name appears twice across the referenced files | **Informational** — a warning is printed, the duplicate is silently deduplicated (first occurrence wins), execution continues. |
| A file referenced by a profile's `packages=` does not exist | **Blocks execution** — `EXIT_VALIDATION_ERROR` at profile-load time, before any role runs. |
| A declared package name is not installed and is not resolvable in any official repo (`pacman -Si` fails) | **Blocks that role's convergence** — the `package` role returns `EXIT_VALIDATION_ERROR` for that check; other declared packages are still checked and reported, but `apply()` does not run for any of them until the workspace is fixed. This is intentional: AUR packages are out of scope for the `package` role in this version (see `docs/decisions/0004-no-aur-role-yet.md`), so an AUR-only name in this file is a workspace bug, not something the engine will silently skip. |
| A package is installed and explicitly requested (`pacman -Qqe`) but not declared in any file the active profile references | **Informational** — reported by `check` and by `archwright drift` as `status=undeclared` (official) or `status=undeclared-foreign` (AUR/foreign). Never removed automatically. |
