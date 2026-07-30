#!/usr/bin/env bash
# lib/commands/asset.sh — `archwright asset <action>` dispatcher.
#
# Owns its own argument parsing rather than reusing bin/archwright's
# generic --workspace/--profile loop: asset actions take a positional
# path and action-specific flags that don't apply to
# validate/plan/converge/drift. Each action sources its own
# lib/commands/asset_<action>.sh.
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

cmd_asset() {
  local action="${1:-}"
  [[ -n "$action" ]] || archwright_die "$EXIT_UNEXPECTED" "usage: archwright asset <capture> ..."
  shift

  case "$action" in
    capture)
      # shellcheck source=lib/commands/asset_capture.sh
      source "${ARCHWRIGHT_LIB_DIR}/commands/asset_capture.sh"
      cmd_asset_capture "$@"
      ;;
    *)
      archwright_die "$EXIT_UNEXPECTED" "unknown 'archwright asset' action: '${action}' (expected: capture)"
      ;;
  esac
}
