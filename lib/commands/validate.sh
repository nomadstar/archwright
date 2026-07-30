#!/usr/bin/env bash
# lib/commands/validate.sh — `archwright validate`
#
# Validates workspace structure and every profile it declares. Never
# touches the running system: no pacman/systemctl calls happen here.
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

cmd_validate() {
  local workspace="$1"
  echo "[archwright] validating workspace: ${workspace}"
  if archwright_validate_workspace "$workspace"; then
    echo "[archwright] OK — workspace is valid (spec v${ARCHWRIGHT_SPEC_VERSION})"
    return "$EXIT_OK"
  fi
  echo "[archwright] INVALID — see warnings above" >&2
  return "$EXIT_VALIDATION_ERROR"
}
