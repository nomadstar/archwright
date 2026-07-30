#!/usr/bin/env bash
# lib/roles/assets.sh — the `assets` role.
#
# workspace -> system direction (ADR 0014's "restore"). Copies each
# declared asset's payload to its destination under $HOME and chmods it to
# the declared mode. Never removes a destination file (see
# docs/decisions/0005-no-automatic-removal.md, same invariant as
# package/service). Never follows a symlink at the destination — if
# something else already put a symlink where an asset should go, this
# role refuses to overwrite it rather than silently replacing it.
#
# Unlike package/service, assets are not scoped by profile: there is no
# `assets=` key in profiles/*.conf (ADR 0014 defines none), so this role
# always acts on every manifest under assets/manifest/*.conf regardless
# of which --profile is active. This mirrors how `archwright validate`
# already checks every asset manifest independent of --profile.
#
# Calling convention (see lib/contract.sh):
#   role_check  <workspace>
#   role_apply  <workspace>
#   role_verify <workspace>
# No declared-file arguments — the manifest list is discovered directly
# under <workspace>/assets/manifest/, not passed in like packages/services.

# --- internal helpers --------------------------------------------------

_assets_manifest_ids() {
  local workspace="$1"
  shopt -s nullglob
  local mf
  for mf in "${workspace}"/assets/manifest/*.conf; do
    basename "$mf" .conf
  done
  shopt -u nullglob
}

_assets_dest() {
  # dest_class=home is the only value spec v0.1 accepts; validated
  # upstream by archwright_try_load_asset_manifest.
  printf '%s/%s\n' "${HOME}" "$ARCHWRIGHT_ASSET_DEST_PATH"
}

_assets_actual_mode() {
  local path="$1"
  printf '%04o' "$(( 8#$(stat -c%a -- "$path" 2>/dev/null || echo 0) & 8#777 ))"
}

# --- contract ------------------------------------------------------------

role_check() {
  local workspace="$1"
  [[ -n "${HOME:-}" ]] || { archwright_warn "assets role: \$HOME is not set"; return "$EXIT_UNEXPECTED"; }

  local id changed=0 errors=0
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! archwright_try_load_asset_manifest "$workspace" "$id"; then
      archwright_log assets check "$id" unresolvable "manifest failed to load"
      errors=$((errors + 1))
      continue
    fi

    local payload
    payload="$(archwright_asset_payload_path "$workspace" "$ARCHWRIGHT_ASSET_PAYLOAD_SHA256")"
    if [[ ! -f "$payload" ]]; then
      archwright_log assets check "$id" unresolvable "payload missing at ${payload#"$workspace"/}"
      errors=$((errors + 1))
      continue
    fi

    local dest
    dest="$(_assets_dest)"
    if [[ -L "$dest" ]]; then
      archwright_log assets check "$id" unresolvable "destination exists as a symlink, refusing"
      errors=$((errors + 1))
      continue
    fi
    if [[ ! -e "$dest" ]]; then
      archwright_log assets check "$id" missing "not present at ${ARCHWRIGHT_ASSET_DEST_PATH}"
      changed=$((changed + 1))
      continue
    fi
    if [[ ! -f "$dest" ]]; then
      archwright_log assets check "$id" unresolvable "destination exists and is not a regular file"
      errors=$((errors + 1))
      continue
    fi

    local actual_sha
    actual_sha="$(sha256sum -- "$dest" | cut -d' ' -f1)"
    if [[ "$actual_sha" == "$ARCHWRIGHT_ASSET_PAYLOAD_SHA256" && "$(_assets_actual_mode "$dest")" == "$ARCHWRIGHT_ASSET_MODE" ]]; then
      archwright_log assets check "$id" ok
    else
      archwright_log assets check "$id" modified "content or mode differs from the declared asset"
      changed=$((changed + 1))
    fi
  done < <(_assets_manifest_ids "$workspace")

  if [[ "$errors" -gt 0 ]]; then
    return "$EXIT_VALIDATION_ERROR"
  elif [[ "$changed" -gt 0 ]]; then
    return "$EXIT_CHANGED"
  fi
  return "$EXIT_OK"
}

role_apply() {
  local workspace="$1"
  [[ -n "${HOME:-}" ]] || { archwright_warn "assets role: \$HOME is not set"; return "$EXIT_UNEXPECTED"; }

  local id failed=0
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    archwright_try_load_asset_manifest "$workspace" "$id" || continue

    local payload
    payload="$(archwright_asset_payload_path "$workspace" "$ARCHWRIGHT_ASSET_PAYLOAD_SHA256")"
    [[ -f "$payload" ]] || continue  # check() already reported this as unresolvable

    local dest
    dest="$(_assets_dest)"
    if [[ -L "$dest" ]]; then
      archwright_log assets apply "$id" failed "destination exists as a symlink, refusing to overwrite"
      failed=1
      continue
    fi

    local content_ok=0 mode_ok=0
    if [[ -f "$dest" ]]; then
      local actual_sha
      actual_sha="$(sha256sum -- "$dest" 2>/dev/null | cut -d' ' -f1)"
      [[ "$actual_sha" == "$ARCHWRIGHT_ASSET_PAYLOAD_SHA256" ]] && content_ok=1
      [[ "$(_assets_actual_mode "$dest")" == "$ARCHWRIGHT_ASSET_MODE" ]] && mode_ok=1
    fi
    [[ "$content_ok" -eq 1 && "$mode_ok" -eq 1 ]] && continue  # already conforms

    if [[ "$content_ok" -eq 0 ]]; then
      mkdir -p "$(dirname "$dest")"
      if ! cp --no-preserve=mode,ownership -- "$payload" "$dest"; then
        archwright_log assets apply "$id" failed "copy failed"
        failed=1
        continue
      fi
    fi
    if ! chmod "$ARCHWRIGHT_ASSET_MODE" -- "$dest" 2>/dev/null; then
      archwright_log assets apply "$id" failed "chmod failed"
      failed=1
      continue
    fi
    archwright_log assets apply "$id" restored "dest=${ARCHWRIGHT_ASSET_DEST_PATH}"
  done < <(_assets_manifest_ids "$workspace")

  [[ "$failed" -ne 0 ]] && return "$EXIT_APPLY_FAILED"
  return "$EXIT_CHANGED"
}

role_verify() {
  local workspace="$1"
  [[ -n "${HOME:-}" ]] || { archwright_warn "assets role: \$HOME is not set"; return "$EXIT_UNEXPECTED"; }

  local id failures=0
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    archwright_try_load_asset_manifest "$workspace" "$id" || continue

    local dest
    dest="$(_assets_dest)"
    if [[ ! -f "$dest" || -L "$dest" ]]; then
      archwright_log assets verify "$id" still-missing
      failures=$((failures + 1))
      continue
    fi

    local actual_sha
    actual_sha="$(sha256sum -- "$dest" | cut -d' ' -f1)"
    if [[ "$actual_sha" == "$ARCHWRIGHT_ASSET_PAYLOAD_SHA256" && "$(_assets_actual_mode "$dest")" == "$ARCHWRIGHT_ASSET_MODE" ]]; then
      archwright_log assets verify "$id" ok
    else
      archwright_log assets verify "$id" still-mismatched
      failures=$((failures + 1))
    fi
  done < <(_assets_manifest_ids "$workspace")

  [[ "$failures" -eq 0 ]] && return "$EXIT_OK"
  return "$EXIT_VERIFY_FAILED"
}
