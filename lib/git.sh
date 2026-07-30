#!/usr/bin/env bash
# lib/git.sh — provider-agnostic git plumbing shared by `workspace publish`.
#
# ADR 0015: git, add, commit, push, fetch/pull are NOT provider-specific —
# once a remote URL is known, transport is plain git regardless of which
# platform it points at. No lib/providers/<name>.sh file may call git
# directly; they only resolve platform facts (auth, repo existence,
# remote URL). This file is the only place git plumbing lives.
#
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

git_has_commit() {
  local workspace="$1"
  git -C "$workspace" rev-parse --verify -q HEAD >/dev/null 2>&1
}

git_is_clean() {
  local workspace="$1"
  [[ -z "$(git -C "$workspace" status --porcelain 2>/dev/null)" ]]
}

git_current_branch() {
  local workspace="$1"
  git -C "$workspace" rev-parse --abbrev-ref HEAD 2>/dev/null
}

git_local_head() {
  local workspace="$1"
  git -C "$workspace" rev-parse HEAD 2>/dev/null
}

# git_remote_url <workspace> <remote-name> -> prints the configured URL, or
# nothing (exit nonzero) if that remote isn't configured at all.
git_remote_url() {
  local workspace="$1" remote="$2"
  git -C "$workspace" remote get-url "$remote" 2>/dev/null
}

# git_set_remote <workspace> <remote-name> <url>
# Low-level upsert only — add if the remote name doesn't exist yet,
# set-url if it does. Deciding whether it is SAFE to call this (the
# non-destructive "never replace a remote pointing somewhere else"
# algorithm) is the orchestrator's job (lib/commands/workspace_publish.sh),
# not this function's — this is plumbing, not policy.
git_set_remote() {
  local workspace="$1" remote="$2" url="$3"
  if git -C "$workspace" remote get-url "$remote" >/dev/null 2>&1; then
    git -C "$workspace" remote set-url "$remote" "$url"
  else
    git -C "$workspace" remote add "$remote" "$url"
  fi
}

git_push() {
  local workspace="$1" remote="$2" branch="$3"
  git -C "$workspace" push "$remote" "$branch" 2>&1
}

# git_ls_remote_head <url> <branch> -> prints the remote's current SHA for
# refs/heads/<branch>, or nothing if the branch doesn't exist there yet.
git_ls_remote_head() {
  local url="$1" branch="$2"
  git ls-remote "$url" "refs/heads/${branch}" 2>/dev/null | awk '{print $1}'
}
