#!/usr/bin/env bash
# lib/commands/workspace_publish.sh — `archwright workspace publish`
#
# workspace -> remote direction (ADR 0015). Implements the ten-step order
# from that ADR exactly: every local, read-only check runs to completion
# BEFORE any network call or remote mutation — this ordering is itself
# the security property, not an implementation detail. Never stages or
# commits anything itself (requires a clean working tree as a hard
# precondition). Never creates a public repository, in any form, behind
# any flag. Never replaces an existing remote that points somewhere else.
#
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

readonly ARCHWRIGHT_REPO_NAME_PATTERN='^[a-zA-Z0-9._-]+$'

cmd_workspace_publish() {
  local workspace="" provider_name="" repo_name="" remote_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace)
        [[ $# -ge 2 ]] || archwright_die "$EXIT_UNEXPECTED" "--workspace requires a value"
        workspace="$2"; shift 2 ;;
      --provider)
        [[ $# -ge 2 ]] || archwright_die "$EXIT_UNEXPECTED" "--provider requires a value"
        provider_name="$2"; shift 2 ;;
      --repo)
        [[ $# -ge 2 ]] || archwright_die "$EXIT_UNEXPECTED" "--repo requires a value"
        repo_name="$2"; shift 2 ;;
      --remote)
        [[ $# -ge 2 ]] || archwright_die "$EXIT_UNEXPECTED" "--remote requires a value"
        remote_name="$2"; shift 2 ;;
      -*)
        archwright_die "$EXIT_UNEXPECTED" "unknown argument: $1" ;;
      *)
        archwright_die "$EXIT_UNEXPECTED" "unexpected argument: $1" ;;
    esac
  done

  [[ -n "$workspace" ]] || archwright_die "$EXIT_UNEXPECTED" "--workspace is required"
  [[ -d "$workspace" ]] || archwright_die "$EXIT_UNEXPECTED" "workspace directory not found: ${workspace}"
  workspace="$(cd "$workspace" && pwd)"
  [[ -n "$provider_name" ]] || archwright_die "$EXIT_UNEXPECTED" "--provider is required"

  local provider_file="${ARCHWRIGHT_LIB_DIR}/providers/${provider_name}.sh"
  [[ -f "$provider_file" ]] || archwright_die "$EXIT_UNEXPECTED" "unknown provider '${provider_name}' (no ${provider_file})"

  # --- step 1: validate the workspace -------------------------------------
  if ! archwright_validate_workspace "$workspace"; then
    archwright_warn "publish: workspace does not validate, see warnings above"
    return "$EXIT_VALIDATION_ERROR"
  fi
  archwright_log workspace publish validate ok

  # --- step 2: a git repo with at least one commit ------------------------
  # shellcheck source=lib/git.sh
  source "${ARCHWRIGHT_LIB_DIR}/git.sh"
  if ! git_has_commit "$workspace"; then
    archwright_warn "publish: ${workspace} is not a git repository with at least one commit — run 'git init' and commit first"
    return "$EXIT_VALIDATION_ERROR"
  fi
  archwright_log workspace publish git-history ok

  # --- step 3: clean working tree, hard precondition ----------------------
  if ! git_is_clean "$workspace"; then
    archwright_warn "publish: working tree is not clean — publish never stages or commits on your behalf:"
    git -C "$workspace" status --porcelain >&2
    return "$EXIT_VALIDATION_ERROR"
  fi
  archwright_log workspace publish working-tree clean

  # --- step 4: secret scan + path validation, BEFORE any network call ----
  if ! "${ARCHWRIGHT_ROOT}/scripts/check-secrets.sh" "$workspace" >&2; then
    archwright_warn "publish: secret scan of the workspace failed, see findings above"
    return "$EXIT_VALIDATION_ERROR"
  fi
  archwright_log workspace publish secret-scan ok

  # --- step 5: provider availability + authentication, never a fallback --
  # shellcheck source=/dev/null
  source "$provider_file"
  if ! provider_available; then
    archwright_warn "publish: provider '${provider_name}' is not available on this system"
    return "$EXIT_VALIDATION_ERROR"
  fi
  if ! provider_authenticated; then
    archwright_warn "publish: not authenticated with provider '${provider_name}' — never falling back to another provider"
    return "$EXIT_VALIDATION_ERROR"
  fi
  archwright_log workspace publish provider-auth ok "${provider_name}"

  # --- step 6: resolve identity, repo name, expected visibility ----------
  local namespace
  namespace="$(provider_identity)" || true
  [[ -n "$namespace" ]] || archwright_die "$EXIT_UNEXPECTED" "publish: provider '${provider_name}' did not resolve an identity/namespace"

  [[ -n "$repo_name" ]] || repo_name="$(basename "$workspace")"
  if [[ ! "$repo_name" =~ $ARCHWRIGHT_REPO_NAME_PATTERN ]]; then
    archwright_die "$EXIT_UNEXPECTED" "publish: repo name '${repo_name}' does not match ${ARCHWRIGHT_REPO_NAME_PATTERN}"
  fi
  archwright_log workspace publish target ok "namespace=${namespace} repo=${repo_name}"

  # --- step 7: create the repo if it's missing (always private); refuse a
  # pre-existing non-private repo this command didn't create as private --
  if provider_repo_exists "$namespace" "$repo_name"; then
    if ! provider_repo_is_private "$namespace" "$repo_name"; then
      archwright_warn "publish: ${namespace}/${repo_name} already exists on ${provider_name} and is not private — refusing to push into it"
      return "$EXIT_VALIDATION_ERROR"
    fi
    archwright_log workspace publish repo exists "${namespace}/${repo_name} (private)"
  else
    if ! provider_create_repo "$namespace" "$repo_name"; then
      archwright_warn "publish: failed to create ${namespace}/${repo_name} on ${provider_name}"
      return "$EXIT_APPLY_FAILED"
    fi
    archwright_log workspace publish repo created "${namespace}/${repo_name} (private)"
  fi

  local expected_url
  expected_url="$(provider_remote_url "$namespace" "$repo_name")" || true
  [[ -n "$expected_url" ]] || archwright_die "$EXIT_UNEXPECTED" "publish: provider '${provider_name}' did not resolve a remote URL for ${namespace}/${repo_name}"

  # --- step 8: configure the remote, non-destructively --------------------
  # git_remote_url legitimately fails (nonzero) when the remote isn't
  # configured yet — that's an expected state here, not an error, so it
  # must not be a bare statement under bin/archwright's `set -e`.
  [[ -n "$remote_name" ]] || remote_name="$provider_name"
  local current_url
  if ! current_url="$(git_remote_url "$workspace" "$remote_name" 2>/dev/null)"; then
    current_url=""
  fi
  if [[ -z "$current_url" ]]; then
    git_set_remote "$workspace" "$remote_name" "$expected_url"
    archwright_log workspace publish remote configured "${remote_name} -> ${expected_url}"
  elif [[ "$current_url" == "$expected_url" ]]; then
    archwright_log workspace publish remote ok "${remote_name} already correct"
  else
    archwright_warn "publish: remote '${remote_name}' already points at '${current_url}', not '${expected_url}' — refusing to replace it. Use --remote <different-name>, or fix the existing remote yourself."
    return "$EXIT_VALIDATION_ERROR"
  fi

  # --- step 9: push --------------------------------------------------------
  local branch push_output push_rc
  branch="$(git_current_branch "$workspace")" || true
  [[ -n "$branch" ]] || archwright_die "$EXIT_UNEXPECTED" "publish: could not determine the current branch"
  if push_output="$(git_push "$workspace" "$remote_name" "$branch")"; then
    push_rc=0
  else
    push_rc=$?
  fi
  if [[ "$push_rc" -ne 0 ]]; then
    archwright_warn "publish: git push failed:"
    printf '%s\n' "$push_output" >&2
    return "$EXIT_APPLY_FAILED"
  fi
  archwright_log workspace publish push ok "${remote_name}/${branch}"

  # --- step 10: verify remote HEAD matches local HEAD (read-only) --------
  local local_head remote_head
  local_head="$(git_local_head "$workspace")" || true
  remote_head="$(git_ls_remote_head "$expected_url" "$branch")" || true
  if [[ "$remote_head" != "$local_head" ]]; then
    archwright_warn "publish: push reported success but remote HEAD (${remote_head:-<none>}) does not match local HEAD (${local_head}) — this points at something other than a transport failure (e.g. a server-side hook or branch protection silently rejecting part of the push)"
    return "$EXIT_VERIFY_FAILED"
  fi

  archwright_log workspace publish published ok "${namespace}/${repo_name} @ ${local_head}"
  return "$EXIT_OK"
}
