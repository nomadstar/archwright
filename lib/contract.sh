#!/usr/bin/env bash
# lib/contract.sh — shared primitives for the Archwright role contract.
#
# A role is a shell file under lib/roles/<name>.sh that defines three
# functions: role_check, role_apply, role_verify. This file provides the
# logging, exit-code, and dispatch helpers every command and role shares.
#
# Security invariant: this file (and everything it sources) must never
# `source` or `eval` content that originates from a workspace directory.
# Workspace files are data, read with plain `read`/`grep`/`cut` — never code.
#
# Deliberately does NOT `set -e`/`-u`/`pipefail` here: this file is sourced
# by bin/archwright (which does set them) but also by bats unit tests and
# other tooling that must not have its own shell options silently changed
# by a library it imports. Every function below is written to behave
# correctly whether or not the caller has errexit enabled.

# --- Exit codes (stable, documented in docs/contract.md) -------------------
readonly EXIT_OK=0                # success, system already conformed / no drift
readonly EXIT_UNEXPECTED=1        # unexpected internal error (bug, I/O failure)
readonly EXIT_CHANGED=2           # success, changes were applied or are pending
readonly EXIT_VALIDATION_ERROR=3  # workspace/profile/spec is invalid
readonly EXIT_APPLY_FAILED=4      # apply() could not bring the system to spec
readonly EXIT_VERIFY_FAILED=5     # apply() ran but verify() found a mismatch

# --- Logging -----------------------------------------------------------------
# Every log line is machine-parseable: space-separated KEY=VALUE pairs after
# a fixed prefix. Values that contain spaces are not currently emitted by any
# built-in role; if a future role needs to, it must quote the value itself.
#
#   [archwright] role=package action=check item=git status=missing
#
archwright_log() {
  local role="$1" action="$2" item="$3" status="$4"
  shift 4
  local message="${*:-}"
  printf '[archwright] role=%s action=%s item=%s status=%s' "$role" "$action" "$item" "$status"
  if [[ -n "$message" ]]; then
    printf ' message=%q' "$message"
  fi
  printf '\n'
}

archwright_die() {
  # archwright_die <exit-code> <message...>
  local code="$1"
  shift
  printf '[archwright] error: %s\n' "$*" >&2
  exit "$code"
}

archwright_warn() {
  printf '[archwright] warning: %s\n' "$*" >&2
}

# --- Role dispatch -------------------------------------------------------
# archwright_run_role <role-name> <stage> <workspace-dir> <declared-file...>
#
# <stage> is one of: check apply verify
# Loads lib/roles/<role-name>.sh (framework code, safe to source) and calls
# role_<stage>. Returns the role's own exit status unchanged.
archwright_run_role() {
  local role="$1" stage="$2"
  shift 2
  local role_file="${ARCHWRIGHT_LIB_DIR}/roles/${role}.sh"
  if [[ ! -f "$role_file" ]]; then
    archwright_die "$EXIT_UNEXPECTED" "unknown role '${role}' (no ${role_file})"
  fi
  # shellcheck source=/dev/null
  source "$role_file"
  local fn="role_${stage}"
  if ! declare -F "$fn" >/dev/null; then
    archwright_die "$EXIT_UNEXPECTED" "role '${role}' does not implement ${fn}()"
  fi
  "$fn" "$@"
}

# --- Small text-processing helpers used by roles and workspace.sh --------

# Read a plain list file: one entry per line, strips comments (#...) and
# blank lines, trims surrounding whitespace. Never executes the file.
archwright_read_list_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] && printf '%s\n' "$line"
  done < "$file"
}

# archwright_uniq_check <file-description> <line1> <line2> ...
# Prints a validation error and returns non-zero if any value repeats.
archwright_check_duplicates() {
  local desc="$1"
  shift
  local seen="" dup_found=0
  local item
  for item in "$@"; do
    if printf '%s\n' "$seen" | grep -qxF "$item"; then
      archwright_warn "duplicate entry '${item}' in ${desc} (later duplicates are ignored)"
      dup_found=1
    fi
    seen="${seen}${item}"$'\n'
  done
  return "$dup_found"
}
