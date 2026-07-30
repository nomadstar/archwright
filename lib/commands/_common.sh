#!/usr/bin/env bash
# lib/commands/_common.sh — shared helpers for CLI subcommands.
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

readonly ARCHWRIGHT_ROLES="package service assets"

# archwright_invoke_role <role> <stage> <workspace>
# Builds the correct argument list for the given role and calls
# archwright_run_role. On return, ARCHWRIGHT_LAST_OUTPUT holds everything
# the role wrote to stdout (its log lines); the function's own return code
# is the role's exit code. Warnings the role writes to stderr are NOT
# captured — they still stream live to the operator.
archwright_invoke_role() {
  local role="$1" stage="$2" workspace="$3"
  case "$role" in
    package)
      if ARCHWRIGHT_LAST_OUTPUT="$(archwright_run_role package "$stage" "$workspace" "${ARCHWRIGHT_PROFILE_PACKAGE_FILES[@]}")"; then
        return "$EXIT_OK"
      else
        return "$?"
      fi
      ;;
    service)
      if ARCHWRIGHT_LAST_OUTPUT="$(archwright_run_role service "$stage" "$workspace" --system "${ARCHWRIGHT_PROFILE_SERVICE_SYSTEM_FILES[@]}" --user "${ARCHWRIGHT_PROFILE_SERVICE_USER_FILES[@]}")"; then
        return "$EXIT_OK"
      else
        return "$?"
      fi
      ;;
    assets)
      # Not scoped by profile — see the note at the top of lib/roles/assets.sh.
      if ARCHWRIGHT_LAST_OUTPUT="$(archwright_run_role assets "$stage" "$workspace")"; then
        return "$EXIT_OK"
      else
        return "$?"
      fi
      ;;
    *)
      archwright_die "$EXIT_UNEXPECTED" "unknown role '${role}'"
      ;;
  esac
}
