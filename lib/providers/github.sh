#!/usr/bin/env bash
# lib/providers/github.sh — GitHub, via the official `gh` CLI.
#
# Platform-only operations (ADR 0015) — no git plumbing here, see lib/git.sh.
# Never touches a credential directly: entirely delegates to `gh`'s own
# already-configured auth session. Not exercised by CI (no real GitHub
# session available there); tests use lib/providers/mock.sh instead.
#
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

provider_available() {
  command -v gh >/dev/null 2>&1
}

provider_authenticated() {
  gh auth status >/dev/null 2>&1
}

provider_identity() {
  gh api user --jq '.login' 2>/dev/null
}

provider_repo_exists() {
  local namespace="$1" name="$2"
  gh repo view "${namespace}/${name}" >/dev/null 2>&1
}

provider_repo_is_private() {
  local namespace="$1" name="$2"
  [[ "$(gh repo view "${namespace}/${name}" --json isPrivate --jq '.isPrivate' 2>/dev/null)" == "true" ]]
}

provider_create_repo() {
  local namespace="$1" name="$2"
  gh repo create "${namespace}/${name}" --private --disable-issues=false >/dev/null 2>&1
}

provider_remote_url() {
  local namespace="$1" name="$2"
  gh repo view "${namespace}/${name}" --json sshUrl --jq '.sshUrl' 2>/dev/null
}
