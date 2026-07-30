# RFC process

**Status: not yet exercised.** This process has never been run for a real
change — it is documented now, before it's needed, so the first real
breaking change has a process to follow instead of an ad-hoc decision.

## When an RFC is required

A change to anything in `docs/spec/` that breaks an existing, valid
workspace — a new required field, a stricter validation rule, a changed
file format — requires an RFC. Additions that don't break existing
workspaces (a new optional key, a new role, a new CLI flag) can go through
a normal pull request with an ADR in `docs/decisions/` explaining the
choice, the same way the MVP's own decisions were recorded.

Changes to `lib/` implementation details that don't change the spec (a
faster parser, a refactor, a bug fix) never need an RFC — normal PR review
is enough.

## Process

1. Copy `0000-template.md` to `NNNN-short-title.md` (next sequential
   number, four digits).
2. Open a pull request adding just that file. The PR description is not
   the proposal — the file is; keep discussion in PR comments.
3. The RFC must state: what breaks, for whom, and what a workspace author
   has to do to migrate. An RFC with no migration section is incomplete.
4. Once discussion converges, the RFC is merged with its status updated to
   `accepted`, and implementation follows in a separate PR that references
   it.
5. If a spec version bump is warranted (see
   `docs/decisions/0006-spec-versioned-separately-from-engine.md`), the
   RFC says so explicitly.

## Why this exists at all with zero users

Writing the process down now — while it costs nothing to change — is
cheaper than designing it under pressure the first time someone's real
workspace is about to break. See
`docs/decisions/0006-spec-versioned-separately-from-engine.md` for the
reasoning behind treating the spec as a higher-stakes artifact than the
engine's own code.
