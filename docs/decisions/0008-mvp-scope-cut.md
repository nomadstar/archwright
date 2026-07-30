# 0008 — What was cut from the MVP, and why

**Status:** accepted

## Context

The architecture proposal that preceded this repository described a much
larger system: dotfiles management (chezmoi integration), a `hook` role,
AUR support with provenance tracking, a pluggable secrets provider
(sops+age reference implementation), hardware-specific `archinstall`
profiles, and drift-based automatic pruning. Building all of it before
proving the core mechanism works risks shipping something large, untested,
and hard to review — the opposite of what the phased rollout asked for.

## Decision

This release implements exactly: the CLI (`validate`/`plan`/`converge`/
`drift`), the `check/apply/verify` contract, two roles (`package`,
`service`), and Workspace Spec v0 covering `.archwright-version`,
`profiles/`, `packages/`, `services/`. Everything else is deferred, each
with its own ADR explaining why:

| Deferred | Why | ADR |
|---|---|---|
| `dotfiles` role | Needs a decision about delegating to chezmoi vs. reimplementing symlink management — a design question, not a small addition. | — (future RFC) |
| `hook` role | Executes arbitrary workspace-declared commands — directly conflicts with the "never execute workspace content" invariant unless very carefully scoped. | 0012 |
| AUR support | Needs a provenance/verification story before it's safe to automate. | 0004 |
| Secrets provider | No role in this release needs secrets; building the abstraction with no real consumer risks designing it wrong. | spec page marked not-implemented |
| Hardware-specific `archinstall` profiles, bootstrap | Destructive (partitioning) and machine-specific — explicitly out of scope per the implementation brief. | — |
| Automatic pruning (remove/disable undeclared items) | Destructive; needs its own safety design. | 0005 |

## Rationale

Each of these is either destructive, security-sensitive, or a large enough
design question to deserve its own RFC once there's a concrete need driving
it — bundling them into the first release would make the MVP harder to
review and slower to ship, for properties nobody has asked to depend on
yet.

## Consequences

This release is not useful as a complete replacement for manual system
setup — it proves a mechanism, on a narrow but real slice of what a
workstation needs. The roadmap for closing these gaps lives in the
project's broader architecture history, not in this repository's issue
tracker yet (that starts once there's a community to prioritize with).
