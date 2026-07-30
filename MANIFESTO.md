# MANIFESTO

> *Software should not disappear because hardware does.*

---

## Why Archwright Exists

Every operating system eventually becomes unique.

Not because it was designed that way, but because every package installed, every configuration changed, every service enabled, and every script written slowly transforms a clean installation into something personal.

That uniqueness is valuable.

It represents knowledge.

It represents time.

It represents years of experimentation.

Yet today, that knowledge is often trapped inside a single machine.

When a disk fails, a laptop is stolen, or a system becomes unrecoverable, rebuilding that environment frequently depends on memory.

Memory is fragile.

Infrastructure should not depend on memory.

---

## Arch Linux Deserves Better

Arch Linux gives users exceptional control over their systems.

It provides transparent tools.

Simple components.

A philosophy that trusts its users.

But rebuilding an entire workstation still relies largely on manual effort.

Documentation becomes outdated.

Shell history disappears.

Configuration drifts.

Knowledge is lost.

Archwright exists because we believe an operating system should be reproducible without sacrificing the philosophy that makes Arch Linux unique.

---

## We Do Not Want Another Distribution

Archwright is not a replacement for Arch Linux.

It is not another package manager.

It is not another init system.

It is not another configuration language.

It is not another operating system.

Archwright exists to work *with* Arch Linux, not around it.

Whenever possible, native Arch tools should remain the source of truth.

Pacman should remain pacman.

Systemd should remain systemd.

Arch should remain Arch.

---

## Infrastructure Is Knowledge

An operating system is more than files on a disk.

It is the collection of decisions that transformed a clean installation into a working environment.

Those decisions deserve to be documented.

Versioned.

Reviewed.

Audited.

Recovered.

Shared.

Infrastructure is knowledge.

Knowledge deserves permanence.

---

## Simplicity Is a Feature

Every abstraction has a cost.

Every layer hides information.

Every convenience introduces assumptions.

Archwright should only abstract what is necessary to make systems reproducible.

If a feature makes the framework harder to understand than the problem it solves, it probably does not belong.

Small components.

Clear responsibilities.

Explicit behavior.

Predictable execution.

These are not implementation details.

They are design principles.

---

## The System Is the State

Archwright does not maintain a hidden database describing reality.

Reality is the operating system itself.

The framework should inspect the current state, compare it with the desired state, and converge only what is necessary.

Truth should never exist in two places.

---

## Reproducibility Before Automation

Automation is useful.

Reproducibility is essential.

A script that installs packages once is automation.

A documented system that can be reconstructed years later is reproducibility.

Archwright exists for the second goal.

Automation is merely one of the tools used to achieve it.

---

## Open by Design

The framework belongs to everyone.

Personal workspaces belong to their owners.

The engine should remain reusable.

The implementation should remain personal.

By separating the framework from the user's workspace, knowledge becomes portable without exposing private information.

---

## Documentation Is Part of the System

Code explains how.

Documentation explains why.

Both are required to preserve knowledge.

Architecture decisions should survive their authors.

The system should remain understandable long after its original contributors are gone.

---

## Community Before Complexity

The best infrastructure is not the one with the most features.

It is the one that people can understand, improve, and trust.

Every contribution should leave the project simpler than it found it.

Every new feature should justify the complexity it introduces.

Every decision should respect the philosophy of Arch Linux.

---

## Our Goal

We are not trying to build the most powerful configuration framework.

We are trying to make sure that no one has to rebuild years of knowledge from memory ever again.

A computer can fail.

Knowledge should not.
