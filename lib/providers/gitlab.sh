#!/usr/bin/env bash
# lib/providers/gitlab.sh — GitLab, via the official `glab` CLI.
#
# Platform-only operations (ADR 0015) — no git plumbing here, see lib/git.sh.
# Never touches a credential directly: entirely delegates to `glab`'s own
# already-configured auth session. Not exercised by CI (no real GitLab
# session available there); tests use lib/providers/mock.sh instead.
#
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

provider_available() {
  command -v glab >/dev/null 2>&1
}

provider_authenticated() {
  glab auth status >/dev/null 2>&1
}

provider_identity() {
  glab api user --jq '.username' 2>/dev/null
}

provider_repo_exists() {
  local namespace="$1" name="$2"
  glab repo view "${namespace}/${name}" >/dev/null 2>&1
}

provider_repo_is_private() {
  local namespace="$1" name="$2"
  local visibility
  visibility="$(glab api "projects/$(printf '%s%%2F%s' "$namespace" "$name")" --jq '.visibility' 2>/dev/null)"
  [[ "$visibility" == "private" ]]
}

provider_create_repo() {
  local namespace="$1" name="$2"
  glab repo create "${namespace}/${name}" --private >/dev/null 2>&1
}

provider_remote_url() {
  local namespace="$1" name="$2"
  glab api "projects/$(printf '%s%%2F%s' "$namespace" "$name")" --jq '.ssh_url_to_repo' 2>/dev/null
}
