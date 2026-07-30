# 0015 — Private Git provider publication

**Status:** proposed, pending implementation

## Context

ADR 0014 makes a workspace fully reproducible on disk, but reproducible
knowledge that only exists on one machine is exactly the failure mode the
project's manifesto opens with. Getting a workspace onto a remote — so a
disk failure or a stolen laptop doesn't take the workspace with it — is a
distinct concern from anything `capture`/`converge` does: it means network
I/O and mutating an account on a third-party service, a risk class this
project has not taken on anywhere else in its design.

This ADR was revised twice from its first draft. The corrections that
matter most: the provider interface originally included `push`/`pull`/
`clone`, which are not provider-specific operations; the command
originally would have replaced an existing `origin` remote silently; and
the ordering of local-vs-remote validation was not specified precisely
enough to guarantee secrets are checked before any network call is made.
All three are fixed below.

## Decision

### One command, one direction

```
archwright workspace publish --provider <name> [--repo <name>] [--remote <name>]
```

Direction: workspace → remote. This is the only command this ADR defines.
It never runs implicitly from `converge`, `plan`, or any other existing
command — publishing is always a deliberate, separate invocation.

### The provider interface is reduced to platform-only operations

An earlier draft gave each provider its own `push`/`pull`/`clone`. Those
are not provider-specific — once a remote URL is known, transport is
plain git, identical whether the URL points at GitHub, GitLab, Forgejo, or
Gitea. Duplicating them per provider would mean four implementations of
the same `git push` for no reason. The interface is cut down to what
genuinely differs per platform:

```
provider_available()
provider_authenticated()
provider_identity()
provider_repo_exists(namespace, name)
provider_create_repo(namespace, name)   # always private — no visibility parameter exists
provider_remote_url(namespace, name)
```

Git plumbing moves to a provider-agnostic layer:

```
lib/git.sh
  git_is_clean(workspace)
  git_current_branch(workspace)
  git_remote_url(workspace, remote_name)
  git_set_remote(workspace, remote_name, url)   # only ever called when non-destructive (see below)
  git_push(workspace, remote_name, branch)
  git_ls_remote_head(url, branch)
```

`lib/commands/workspace_publish.sh` is the only place that calls both
layers together; no `lib/providers/<name>.sh` file contains a `git push`
call, and no file outside `lib/providers/` mentions `gh` or `glab` by
name.

### Never replace an existing remote silently

An earlier draft would run `git remote set-url origin <url>`
unconditionally. That can silently repoint an existing `origin` at a
different repository than the one the user thinks they're publishing to —
a workspace could end up pushed somewhere unintended with no warning.
Corrected behavior:

1. Resolve the target remote name: `--remote <name>` if given, otherwise
   the provider's own name (`github`, `gitlab`, …) — **not** `origin`.
   Defaulting to the provider name, not `origin`, is what makes "publish
   this same workspace to two providers" work at all: `origin` would
   collide the second time.
2. If that remote name isn't configured yet: proceed to create/configure
   it.
3. If it's configured and already points at the URL `publish` would
   configure: treat this step as already satisfied, continue.
4. If it's configured and points anywhere else: **abort.** Report both
   URLs. No `--force`. The fix is either `--remote <different-name>` or
   the user manually resolving the existing remote themselves — this
   command does not do it for them.

### No automatic staging or commits

`publish` requires, as a hard precondition, a clean working tree in an
already-initialized git repository with at least one commit. It never
runs `git add` or `git commit`, and it never invents a commit message. If
`.git` doesn't exist: abort with instructions to `git init` and commit
first. If the tree is dirty: abort, list what's dirty, do nothing. An
assisted mode (staging + an explicit, user-confirmed commit message) is a
plausible future extension and is explicitly out of scope for v1.

### Repositories are always private

`provider_create_repo` takes no visibility parameter — it only ever
creates a private repository. There is no `--public` flag anywhere in
this design. This isn't "public behind a confirmation prompt," it's not
implemented at all: a flag that can create a public repo is a standing
foot-gun (typo, copy-pasted command, a script that builds the invocation
dynamically) no confirmation step fully closes. If public publication is
ever needed, it is a new ADR with its own review of that specific UX, not
an extension of this one.

## Command semantics — the ten-step order

Local validation runs to completion **before** any network call or remote
mutation. This ordering is itself the security property, not an
implementation detail:

1. Validate the workspace (`archwright validate`-equivalent checks).
2. Verify `.git` exists in the workspace and has at least one commit.
3. Require a clean working tree (`git status --porcelain` empty).
4. Run the secret scan and asset path validations **over the workspace
   contents** — see "Security consequences" below; this is a workspace
   scan, not the engine's own repo scan.
5. Check `provider_available()` and `provider_authenticated()` for the
   requested provider. Not authenticated → abort. **Never fall back to a
   different provider.**
6. Resolve identity/namespace (`provider_identity()`), the target repo
   name (`--repo` or the workspace directory's basename, printed before
   use), and confirm the visibility expectation is private.
7. `provider_repo_exists()`; if not, `provider_create_repo()` (private).
   If the repo already exists on the provider but is **not** private
   (created by hand, outside Archwright), abort — `publish` never pushes
   into a remote repository it didn't create as private itself.
8. Configure the remote non-destructively, per the algorithm above.
9. `git push`.
10. `git_ls_remote_head()` — confirm the remote branch HEAD now matches
    local HEAD. This step is a read-only confirmation, not a mutation; its
    failure means "the push didn't actually land as expected," which is
    reported distinctly from a push that failed outright.

Repo name validated against a strict allowlist (`^[a-zA-Z0-9._-]+$`)
before it's ever passed to a provider's create/exists calls — the one
place in this design where a value with more freedom than a package or
service name (a directory basename) reaches an external command's
argument list.

## Failure and recovery — state machine

```
unpublished        no remote configured under the resolved name
   │  provider_create_repo (idempotent: success if it already exists as private)
   ▼
remote-created      repo exists on the provider, local remote not yet configured
   │  git_set_remote (only if unconfigured or already correct — never destructive)
   ▼
origin-configured   local remote points at the right URL, push not yet confirmed
   │  git_push
   ▼
published           git_ls_remote_head(url, branch) == local HEAD
```

Each `publish` invocation inspects current state first (steps 1–7 are all
read-only) and performs only the transition still pending — the same
check-before-mutate shape `converge` already uses. Re-running after a
failure at any step resumes from the state actually observed, not from
whatever the previous invocation assumed.

- `provider_create_repo` fails after actually creating the repo (e.g. the
  success response is lost to a network error): the next run's
  `provider_repo_exists()` finds it already there and skips straight to
  configuring the remote.
- `git_set_remote` succeeds, `git push` fails (network): the next run
  finds the remote already correct (step 3 of the remote algorithm) and
  retries only the push.
- `git push` itself does not need a bespoke resume mechanism: git does not
  move a remote branch ref until all objects are transferred and
  verified, so an interrupted push leaves the remote in its prior state,
  not a torn one. This ADR relies on that existing guarantee rather than
  re-implementing it.
- Step 10 (`git_ls_remote_head` mismatch) with everything else reporting
  success is treated as its own reportable state — surfaced distinctly
  rather than folded into a generic push failure, since it points at a
  different class of problem (e.g. branch protection or a hook on the
  remote silently rejecting part of the push).

## Security consequences

- Step 4 running before step 5 is the actual point of the ten-step
  order: nothing in this pipeline talks to a provider or touches network
  I/O until the workspace's own content has been checked locally. A
  secret accidentally captured (despite ADR 0014's capture-time denylist —
  defense in depth, not redundancy: capture-time checks a single new file,
  publish-time checks the whole workspace as it stands, including
  anything added by other means) is caught before any remote call, not
  after.
- This requires `scripts/check-secrets.sh` (today scoped to Archwright's
  own repository, run in its own CI) to gain a mode that scans an
  arbitrary workspace directory. Building that generalized scan is a
  dependency of implementing this ADR, not a detail left to the
  implementation PR to improvise.
- Archwright never handles provider credentials directly. `provider_
  authenticated()` shells out to `gh auth status` / `glab auth status` (or
  equivalent); no token is read, stored, or passed through Archwright's
  own code. This keeps the "no secrets provider implemented yet" boundary
  (`docs/spec/secrets-provider-interface.md`) exactly where it already
  was — this ADR does not start Archwright managing secrets, it only
  invokes tools that already manage their own.
- Commit identity is whatever the workspace's own `git config` already
  resolves to. `publish` never sets `user.name`/`user.email` and never
  commits — see "no automatic staging or commits" above — so there is no
  code path where Archwright invents an authorship identity.

## Compatibility with existing ADRs

| ADR | Relationship |
|---|---|
| 0002 (check/apply/verify contract) | `publish` is not a role and doesn't run under `converge`; its own ten-step order plays the same "read-only checks before the one mutating phase" role that `check` → `apply` plays for roles, without reusing the same function names. |
| 0005 (no automatic removal) | Nothing in this ADR deletes a remote repository or force-pushes over remote history. `git push` here is always a fast-forward of a branch this workspace already owns via `origin`-equivalent configuration. |
| 0006 (spec versioned separately) | Publication doesn't touch the workspace spec at all — no manifest or profile format changes. Not applicable. |
| 0007 (never `source`/`eval` workspace content) | `publish` never executes anything from the workspace; it commits and pushes existing, already-committed content and invokes a fixed set of reviewed provider binaries with sanitized arguments. |
| 0010 (roles aren't sandboxed) | Providers and the git-common layer are framework code, same trust model as roles — but they're the first framework code in this project to perform network I/O and mutate a third-party account. Worth its own explicit note in `docs/architecture.md`'s security posture section once implemented, rather than silently inheriting 0010's local-system framing. |
| 0012 (no hook role) | Provider invocations are a fixed, reviewed command set with sanitized arguments (the repo-name allowlist), not arbitrary workspace-declared commands — this is not a reintroduction of what 0012 ruled out. |
| 0014 (declared assets) | `publish` operates on whatever the workspace contains, including any `assets/` captured under ADR 0014, but has no asset-specific logic of its own — from `publish`'s perspective a workspace with assets and one without are identical. |

## Consequences

- A workspace can be pushed to a private remote on any provider with an
  implemented `lib/providers/<name>.sh`, without Archwright ever holding a
  credential itself.
- The same workspace can be published to multiple providers as distinct
  remotes (`--remote github`, `--remote gitlab`, …) without one publish
  invocation disturbing another's remote configuration.
- Nothing about `validate`, `plan`, `converge`, or `drift` changes; this
  is a fully additive command family.
- A workspace author still commits manually before publishing — this ADR
  intentionally does not make "capture an asset" or "edit a profile"
  automatically flow into a pushed remote. That remains a deliberate,
  separate step.

## Scope explicitly deferred

- Public repository creation, in any form, behind any flag.
- Automatic staging/commit ("assisted" publish mode).
- `provider_pull` / `provider_clone` as provider-specific operations —
  once a URL is known, plain `git clone`/`git pull` already work; nothing
  provider-specific is needed for either, so neither is added to the
  interface.
- Cross-provider mirroring or migration.
- Forgejo/Gitea provider implementations (the interface is designed to
  support them; only GitHub and GitLab are implemented against this ADR).
- Any `--force` on remote configuration, repo creation, or push.
