#!/usr/bin/env bash
# lib/providers/mock.sh — test-only provider, no network.
#
# Backs its "remote" with a real local bare git repository under
# $ARCHWRIGHT_MOCK_PROVIDER_HOME, so tests exercise the real git plumbing
# in lib/git.sh (git push, git ls-remote) end-to-end against a real repo,
# not a stubbed function call — while never touching GitHub/GitLab. Used
# by tests/unit/workspace_publish.bats. Never wired into bin/archwright's
# --provider selection for real usage.
#
# Layout under $ARCHWRIGHT_MOCK_PROVIDER_HOME:
#   auth                              present => authenticated
#   identity                          contents => provider_identity's output
#   repos/<namespace>/<name>.git/     the bare repo (its existence => the repo exists)
#   repos/<namespace>/<name>.visibility   "private" or "public"
#
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

provider_available() {
  [[ -n "${ARCHWRIGHT_MOCK_PROVIDER_HOME:-}" ]]
}

provider_authenticated() {
  [[ -f "${ARCHWRIGHT_MOCK_PROVIDER_HOME}/auth" ]]
}

provider_identity() {
  [[ -f "${ARCHWRIGHT_MOCK_PROVIDER_HOME}/identity" ]] || return 1
  cat "${ARCHWRIGHT_MOCK_PROVIDER_HOME}/identity"
}

provider_repo_exists() {
  local namespace="$1" name="$2"
  [[ -d "${ARCHWRIGHT_MOCK_PROVIDER_HOME}/repos/${namespace}/${name}.git" ]]
}

provider_repo_is_private() {
  local namespace="$1" name="$2"
  local f="${ARCHWRIGHT_MOCK_PROVIDER_HOME}/repos/${namespace}/${name}.visibility"
  [[ -f "$f" ]] && [[ "$(cat "$f")" == "private" ]]
}

provider_create_repo() {
  local namespace="$1" name="$2"
  local dir="${ARCHWRIGHT_MOCK_PROVIDER_HOME}/repos/${namespace}/${name}.git"
  if [[ -d "$dir" ]]; then
    return 0  # idempotent: already exists
  fi
  mkdir -p "$(dirname "$dir")"
  git init --bare --quiet "$dir" >/dev/null 2>&1 || return 1
  printf 'private\n' > "${ARCHWRIGHT_MOCK_PROVIDER_HOME}/repos/${namespace}/${name}.visibility"
}

provider_remote_url() {
  local namespace="$1" name="$2"
  printf 'file://%s/repos/%s/%s.git\n' "$ARCHWRIGHT_MOCK_PROVIDER_HOME" "$namespace" "$name"
}
