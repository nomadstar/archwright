# Archwright

A minimal, auditable engine for declaring and converging the state of an
Arch Linux system — without leaving `pacman`/AUR, without a second package
manager, and without becoming a second operating system that manages the
first one.

> **Status: early, experimental (v0.1.0-dev).** The Workspace Specification
> is explicitly v0/unstable (see `docs/spec/`). This release proves one
> property and does little else — read "What this release actually does"
> below before expecting more.

## The property this release exists to prove

> A declarative **workspace** can converge an Arch Linux system towards a
> desired state, and a second convergence over that same state produces no
> changes.

That's it. Everything in this repository is in service of that claim, and
the claim is checked by CI on every push (`tests/integration/idempotency.sh`),
not just asserted in this README.

## What this release actually does

- A CLI — `archwright validate|plan|converge|drift` — see `docs/getting-started.md`.
- Two roles: `package` (official-repo packages via `pacman`) and `service`
  (systemd unit enablement). No AUR, no dotfiles, no hooks, no secrets yet
  — see `docs/decisions/0008-mvp-scope-cut.md` for the full list of what
  was deliberately deferred and why.
- A `check → apply → verify` contract every role follows, documented
  precisely in `docs/contract.md`.
- Workspace Specification v0: two plain-text list formats and one flat
  `key=value` profile format — no YAML/TOML parser, and nothing under a
  workspace directory is ever executed (`docs/decisions/0007`).
- `apply` never removes a package or disables a service —
  `docs/decisions/0005-no-automatic-removal.md`.

## Archwright vs. your workspace

Archwright is the engine — it ships with **no personal configuration, no
secrets, no hostnames, no dotfiles**. You point it at a *workspace*: a
directory (typically your own private Git repository) that declares what
your system should look like, following `docs/spec/`. The relationship is
the same one Terraform has to a directory of `.tf` files — see
`docs/architecture.md`.

```
your-private-workspace/          archwright/ (this repo, public)
├── .archwright-version    <-->  reads/validates against docs/spec/
├── profiles/*.conf               engine, roles, CLI — no data of yours
├── packages/*.txt
└── services/*.txt
```

## Try it

```sh
git clone https://github.com/nomadstar/archwright.git
cd archwright
./bin/archwright validate --workspace examples/minimal-workspace
./bin/archwright plan     --workspace examples/minimal-workspace --profile ci
sudo ./bin/archwright converge --workspace examples/minimal-workspace --profile ci
```

Full walkthrough, including the idempotency check, in
`docs/getting-started.md`.

## Documentation

| | |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | What's actually built, and the data flow through it |
| [`docs/contract.md`](docs/contract.md) | The role contract: exit codes, message format, what each stage may and may not do |
| [`docs/spec/`](docs/spec/) | Workspace Specification v0 (unstable) |
| [`docs/decisions/`](docs/decisions/) | ADRs — every non-obvious choice, and why |
| [`docs/rfcs/`](docs/rfcs/) | Process for changes that break the spec |
| [`docs/testing.md`](docs/testing.md) | How to run the tests, including the idempotency integration test |
| [`docs/getting-started.md`](docs/getting-started.md) | Full command walkthrough |

## Contributing

See `CONTRIBUTING.md`. Found a security issue? See `SECURITY.md` — please
don't open a public issue for it.

## License

Apache License 2.0 — see `LICENSE`.
