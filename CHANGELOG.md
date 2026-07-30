# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Two version numbers matter separately in this project — see
`docs/decisions/0006-spec-versioned-separately-from-engine.md`: the engine
version below, and the Workspace Specification version
(`ARCHWRIGHT_SPEC_VERSION` in `lib/workspace.sh`, currently `0`).

## [Unreleased] — 0.1.0-dev

Initial, deliberately minimal release. Exists to demonstrate one property:
a declarative workspace converges idempotently. See `docs/architecture.md`.

### Added

- CLI: `archwright validate|plan|converge|drift` (`bin/archwright`).
- `check` / `apply` / `verify` role contract (`docs/contract.md`).
- Two roles: `package` (official-repo packages via `pacman`) and `service`
  (systemd unit enablement, system and user scope).
- Workspace Specification v0: `.archwright-version`, `profiles/*.conf`,
  `packages/*.txt`, `services/*.txt` (`docs/spec/`).
- `examples/minimal-workspace/` — fixture, CI subject, and docs example.
- Unit tests (`tests/unit/`, bats) and an integration idempotency test
  (`tests/integration/idempotency.sh`) run in CI against an ephemeral,
  systemd-capable Arch Linux container.
- `scripts/check-secrets.sh`, run in CI on every push.
- Governance/community files: `LICENSE` (Apache-2.0), `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, `SECURITY.md`.
- Twelve ADRs (`docs/decisions/`) recording every non-obvious scope cut and
  design choice made to keep this first release small and auditable.

### Explicitly not included

AUR packages, dotfiles, hooks, secrets/any provider integration, hardware-
specific `archinstall` profiles, automatic removal/disabling of undeclared
items. See `docs/decisions/0008-mvp-scope-cut.md` for the full list and
the reasoning behind each cut.
