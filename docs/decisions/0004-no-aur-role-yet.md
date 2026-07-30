# 0004 — No AUR role yet

**Status:** accepted (scope cut for this release)

## Context

Real Arch systems mix official-repo packages with AUR packages. The
original architecture discussion designed for an `aur.txt` file recording
provenance (commit, `PKGBUILD` checksum, justification) precisely because
AUR packages carry more risk (arbitrary build scripts, no official review)
than official-repo installs.

## Decision

The `package` role in this release manages official-repo packages only
(`pacman -S`, resolving names via `pacman -Si`). A declared name that isn't
in any official repo is reported as `status=unresolvable` and blocks that
role's `apply` — it is treated as a workspace bug, not silently skipped or
routed to an AUR helper.

## Rationale

- Installing from AUR means running a build process not controlled by
  Arch's own review — bringing that into the MVP means designing the
  provenance/verification story (commit pinning, checksum validation)
  *before* proving the core idempotency claim, which is exactly the scope
  creep the phased rollout is meant to avoid.
- The `package` role's contract (docs/contract.md) is easier to reason
  about and to test in CI when "install" always means one well-understood
  operation (`pacman -S --needed --noconfirm`) against one trust boundary
  (official repos).

## Consequences

- A workspace that needs AUR packages cannot yet declare them through
  Archwright — they remain manually installed until an `aur` role (or an
  extension of `package`) is designed, most likely as a documented RFC
  given the provenance/security surface involved.
- `pacman -Qqem` (foreign/AUR explicit packages) is still queried for the
  informational "undeclared" report, so a workspace author at least sees
  what's installed outside the engine's control — it just isn't managed.
