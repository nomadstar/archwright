# 0005 — No automatic package removal or service disabling

**Status:** accepted

## Context

A fully symmetric convergence engine would also remove packages and
disable services that are installed/enabled but not declared, the same
way Terraform can destroy a resource removed from configuration. The
original architecture proposal flagged this as a real risk area
("undetected drift") and recommended starting report-only.

## Decision

In this release, `apply` only installs missing declared packages and
enables missing declared units. It never runs `pacman -R`/`-Rns` and never
runs `systemctl disable`. Undeclared-but-present items are reported
(`status=undeclared` / `undeclared-foreign`) by `check` and by `archwright
drift`, never acted on.

## Rationale

- Removal is destructive and much harder to make safe generically: removing
  a package can cascade through dependents in ways installation never does,
  and disabling a service can be the difference between a reachable and an
  unreachable machine. The blast radius of "converge did too little" is
  strictly smaller than "converge deleted something you needed."
- The MVP's one job is to prove the idempotency property on the safe half
  of convergence (install/enable) before extending it to the unsafe half.

## Consequences

- A workspace cannot yet fully express "this and only this" — drift
  (undeclared items) has to be resolved by a human reading the report, not
  by the engine.
- Any future `--prune`-style flag that does remove/disable must be opt-in,
  almost certainly gated behind its own explicit flag and its own RFC,
  never the default behavior of `converge`.
