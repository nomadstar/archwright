#!/usr/bin/env bash
# lib/commands/workspace.sh — `archwright workspace <action>` dispatcher.
#
# Mirrors lib/commands/asset.sh's shape: owns its own argument parsing,
# each action sources its own lib/commands/workspace_<action>.sh.
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

cmd_workspace() {
  local action="${1:-}"
  [[ -n "$action" ]] || archwright_die "$EXIT_UNEXPECTED" "usage: archwright workspace <publish> ..."
  shift

  case "$action" in
    publish)
      # shellcheck source=lib/commands/workspace_publish.sh
      source "${ARCHWRIGHT_LIB_DIR}/commands/workspace_publish.sh"
      cmd_workspace_publish "$@"
      ;;
    *)
      archwright_die "$EXIT_UNEXPECTED" "unknown 'archwright workspace' action: '${action}' (expected: publish)"
      ;;
  esac
}
