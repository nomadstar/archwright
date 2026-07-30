#!/usr/bin/env bash
# lib/commands/asset_list.sh — `archwright asset list`
#
# Read-only. Lists every declared asset in a workspace. Fails (does not
# just print nothing) if assets/ doesn't validate — a corrupt manifest is
# not something `list` should silently skip past.
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

cmd_asset_list() {
  local workspace=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace)
        [[ $# -ge 2 ]] || archwright_die "$EXIT_UNEXPECTED" "--workspace requires a value"
        workspace="$2"; shift 2 ;;
      -*)
        archwright_die "$EXIT_UNEXPECTED" "unknown argument: $1" ;;
      *)
        archwright_die "$EXIT_UNEXPECTED" "unexpected argument: $1 (archwright asset list takes no positional arguments)" ;;
    esac
  done

  [[ -n "$workspace" ]] || archwright_die "$EXIT_UNEXPECTED" "--workspace is required"
  [[ -d "$workspace" ]] || archwright_die "$EXIT_UNEXPECTED" "workspace directory not found: ${workspace}"
  workspace="$(cd "$workspace" && pwd)"

  if ! archwright_validate_asset_manifests "$workspace"; then
    archwright_warn "asset list: assets/ under ${workspace} does not validate, see warnings above"
    return "$EXIT_VALIDATION_ERROR"
  fi

  shopt -s nullglob
  local manifest_files=("${workspace}"/assets/manifest/*.conf)
  shopt -u nullglob

  if [[ "${#manifest_files[@]}" -eq 0 ]]; then
    echo "[archwright] no assets declared in ${workspace}"
    return "$EXIT_OK"
  fi

  local mf id
  for mf in "${manifest_files[@]}"; do
    id="$(basename "$mf" .conf)"
    archwright_try_load_asset_manifest "$workspace" "$id"
    archwright_log asset list "$id" declared \
      "dest=${ARCHWRIGHT_ASSET_DEST_PATH} size=${ARCHWRIGHT_ASSET_SIZE} mode=${ARCHWRIGHT_ASSET_MODE} sha256=${ARCHWRIGHT_ASSET_PAYLOAD_SHA256}"
  done

  return "$EXIT_OK"
}
