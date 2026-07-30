# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Two version numbers matter separately in this project — see
`docs/decisions/0006-spec-versioned-separately-from-engine.md`: the engine
version below, and the Workspace Specification version
(`ARCHWRIGHT_SPEC_VERSION` in `lib/workspace.sh`, currently `0.1`).

## [Unreleased] — 0.1.0-dev

Initial, deliberately minimal release. Exists to demonstrate one property:
a declarative workspace converges idempotently. See `docs/architecture.md`.

### Added

- CLI: `archwright validate|plan|converge|drift` (`bin/archwright`).
- `check` / `apply` / `verify` role contract (`docs/contract.md`).
- Three roles: `package` (official-repo packages via `pacman`), `service`
  (systemd unit enablement, system and user scope), and `assets`
  (individually declared files under `$HOME`, restore direction).
- Workspace Specification v0.1: `.archwright-version`, `profiles/*.conf`,
  `packages/*.txt`, `services/*.txt`, `assets/manifest/*.conf` +
  `assets/payload/<sha256>` (`docs/spec/`) — the `assets/` addition is a
  minor, additive spec change per the versioning policy in ADR 0006.
- `archwright asset capture|scan|list`
  (`docs/decisions/0014-declared-assets-and-capture-restore-lifecycle.md`):
  explicit, content-addressed capture of files a configuration depends on
  (wallpapers, scripts, fonts) — never inferred, with a hard denylist
  (`.ssh`, `.gnupg`, `.env*`, keys, shell history — no override) and a
  content-addressed, deduplicated payload store.
- `examples/minimal-workspace/` — fixture, CI subject, and docs example.
- Unit tests (`tests/unit/`, bats) and an integration idempotency test
  (`tests/integration/idempotency.sh`) run in CI against an ephemeral,
  systemd-capable Arch Linux container.
- `scripts/check-secrets.sh`, run in CI on every push.
- Governance/community files: `LICENSE` (Apache-2.0), `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, `SECURITY.md`.
- ADRs (`docs/decisions/`) recording every non-obvious scope cut and
  design choice made to keep this release small and auditable, including
  the `assets` design (0014) and the versioning policy amendment (0006).

### Explicitly not included

AUR packages, dotfiles (symlink/templating management), hooks, secrets/any
provider integration, hardware-specific `archinstall` profiles, automatic
removal/disabling of undeclared items, publishing a workspace to a remote
git provider (designed in ADR 0015, not yet implemented). See
`docs/decisions/0008-mvp-scope-cut.md` for the full list and the reasoning
behind each cut.
