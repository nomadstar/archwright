# 0001 — Bash orchestrator instead of Ansible-on-localhost

**Status:** accepted

## Context

Archwright needs to converge a single, local Arch Linux system towards a
declared state. Ansible is the obvious off-the-shelf answer: mature,
idempotent-by-convention modules, a large ecosystem. Running it against
`localhost` is a well-known pattern.

## Decision

Use a small bash orchestrator (`lib/contract.sh` + `lib/commands/*.sh` +
`lib/roles/*.sh`) instead of Ansible.

## Rationale

- The entire target is one machine, executed synchronously, with no
  inventory, no fact-gathering across hosts, and no need for a control
  node/managed-node split. Ansible's core value proposition (orchestrating
  many hosts) doesn't apply here.
- A contributor can read `lib/contract.sh` top to bottom in a few minutes.
  Reading "how does Ansible decide a task is idempotent" requires
  understanding a much larger runtime.
- Zero additional runtime dependency beyond `bash` (already present on
  every Arch system) and the standard toolchain (`pacman`, `systemctl`,
  `grep`, `awk`) — no Python virtualenv, no `ansible-core` version pinning.
- The explicit `check/apply/verify` contract (ADR 0002) gives most of what
  Ansible's module idempotency conventions give, without adopting its
  module API or YAML task format.

## Consequences

- We give up Ansible's large module library — if a future role needs
  something Ansible already has a mature module for, that's a real cost,
  weighed case by case.
- We own more of the "did this actually work" verification logic
  ourselves, per role, rather than trusting a module's built-in checks.
- Revisit if/when Archwright needs to manage more than one host at once
  (see the original architecture proposal's roadmap) — that's the point
  where Ansible's actual value proposition starts to apply.
