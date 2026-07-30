#!/usr/bin/env bash
# lib/workspace.sh — loader and validator for Workspace Spec v0.
#
# See docs/spec/ for the authoritative, human-readable specification.
# This file is the reference implementation of that spec: if the two ever
# disagree, the spec is what a workspace author should trust, and this file
# has a bug.
#
# Security invariant: workspace content is only ever read line-by-line with
# `read`/grep-style parsing. Nothing under a workspace directory is ever
# sourced, eval'd, or executed.
#
# Deliberately does NOT `set -e`/`-u`/`pipefail` (see the same note at the
# top of lib/contract.sh) — this file is sourced by test harnesses too.
#
# Two layers are exposed on purpose:
#   archwright_try_load_profile  — never exits, returns 0/1, used by
#                                   `validate` to check every profile and
#                                   report every problem in one pass.
#   archwright_load_profile      — throwing wrapper used by plan/converge/
#                                   drift, which only ever need ONE profile
#                                   and should abort immediately if it is bad.

readonly ARCHWRIGHT_SPEC_VERSION="0.1"
readonly ARCHWRIGHT_PROFILE_ALLOWED_KEYS="name description packages services_system services_user"
readonly ARCHWRIGHT_PROFILE_REQUIRED_KEYS="name packages"
readonly ARCHWRIGHT_ASSET_ALLOWED_KEYS="dest_class dest_path payload_sha256 size mode"
readonly ARCHWRIGHT_ASSET_REQUIRED_KEYS="dest_class dest_path payload_sha256 size mode"
readonly ARCHWRIGHT_ASSET_ID_PATTERN='^[a-z0-9][a-z0-9._-]*$'

# --- .archwright-version ---------------------------------------------------

archwright_read_version_file() {
  local workspace="$1"
  local file="${workspace}/.archwright-version"
  [[ -f "$file" ]] || { archwright_warn ".archwright-version missing at ${file}"; return 1; }
  local content
  content="$(archwright_read_list_file "$file" | head -n1)"
  [[ -n "$content" ]] || { archwright_warn ".archwright-version is present but empty"; return 1; }
  printf '%s\n' "$content"
}

# --- Generic key=value parsing ------------------------------------------
#
# Shared by profiles/*.conf and assets/manifest/*.conf: both are flat
# key=value files with the same comment/whitespace/duplicate/unknown-key
# rules, differing only in which keys are allowed. Parsing logic lives
# here exactly once; format-specific wrappers below just supply the
# allowed-key list and their own required-key checks.

# archwright_parse_kv_file <path> <allowed-keys (space-separated)>
# -> emits validated `key<TAB>value` lines on stdout. Returns non-zero
# (and warns on stderr) on: unknown key, duplicate key, malformed line.
# Never exits the process.
archwright_parse_kv_file() {
  local file="$1" allowed_keys="$2"
  local seen_keys=""
  local lineno=0
  local had_error=0
  local line key value

  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    local raw="$line"
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    if [[ "$line" != *=* ]]; then
      archwright_warn "parse error at ${file}:${lineno}: expected key=value, got: ${raw}"
      had_error=1
      continue
    fi

    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"

    if ! printf ' %s ' "$allowed_keys" | grep -qF " ${key} "; then
      archwright_warn "parse error at ${file}:${lineno}: unknown key '${key}'"
      had_error=1
      continue
    fi
    if printf ' %s ' "$seen_keys" | grep -qF " ${key} "; then
      archwright_warn "parse error at ${file}:${lineno}: duplicate key '${key}'"
      had_error=1
      continue
    fi
    seen_keys="${seen_keys} ${key}"
    printf '%s\t%s\n' "$key" "$value"
  done < "$file"

  return "$had_error"
}

# --- Profile parsing ---------------------------------------------------

# archwright_parse_profile_file <path> -> see archwright_parse_kv_file.
archwright_parse_profile_file() {
  archwright_parse_kv_file "$1" "$ARCHWRIGHT_PROFILE_ALLOWED_KEYS"
}

# archwright_split_csv_to_paths <workspace> <csv> <array-name>
archwright_split_csv_to_paths() {
  local workspace="$1" csv="$2" arr_name="$3"
  [[ -z "$csv" ]] && return 0
  local IFS=','
  local part
  for part in $csv; do
    part="${part#"${part%%[![:space:]]*}"}"
    part="${part%"${part##*[![:space:]]}"}"
    [[ -z "$part" ]] && continue
    eval "${arr_name}+=(\"\${workspace}/\${part}\")"
  done
}

# archwright_try_load_profile <workspace> <profile-name>
# Never exits. Returns 0 and populates the ARCHWRIGHT_PROFILE_* globals on
# success. Returns 1 and leaves warnings on stderr on any validation failure.
archwright_try_load_profile() {
  local workspace="$1" profile="$2"
  local file="${workspace}/profiles/${profile}.conf"

  if [[ ! -f "$file" ]]; then
    archwright_warn "profile '${profile}' not found (expected ${file})"
    return 1
  fi

  local parsed rc=0
  parsed="$(archwright_parse_profile_file "$file")" || rc=1

  ARCHWRIGHT_PROFILE_NAME=""
  ARCHWRIGHT_PROFILE_DESCRIPTION=""
  ARCHWRIGHT_PROFILE_PACKAGE_FILES=()
  ARCHWRIGHT_PROFILE_SERVICE_SYSTEM_FILES=()
  ARCHWRIGHT_PROFILE_SERVICE_USER_FILES=()

  local key value
  while IFS=$'\t' read -r key value; do
    [[ -z "$key" ]] && continue
    case "$key" in
      name) ARCHWRIGHT_PROFILE_NAME="$value" ;;
      description) ARCHWRIGHT_PROFILE_DESCRIPTION="$value" ;;
      packages) archwright_split_csv_to_paths "$workspace" "$value" ARCHWRIGHT_PROFILE_PACKAGE_FILES ;;
      services_system) archwright_split_csv_to_paths "$workspace" "$value" ARCHWRIGHT_PROFILE_SERVICE_SYSTEM_FILES ;;
      services_user) archwright_split_csv_to_paths "$workspace" "$value" ARCHWRIGHT_PROFILE_SERVICE_USER_FILES ;;
    esac
  done <<< "$parsed"

  local req
  for req in $ARCHWRIGHT_PROFILE_REQUIRED_KEYS; do
    case "$req" in
      name)
        if [[ -z "$ARCHWRIGHT_PROFILE_NAME" ]]; then
          archwright_warn "profile '${profile}' is missing required key 'name'"
          rc=1
        fi
        ;;
      packages)
        if [[ "${#ARCHWRIGHT_PROFILE_PACKAGE_FILES[@]}" -eq 0 ]]; then
          archwright_warn "profile '${profile}' is missing required key 'packages'"
          rc=1
        fi
        ;;
    esac
  done

  local f
  for f in "${ARCHWRIGHT_PROFILE_PACKAGE_FILES[@]}" \
           "${ARCHWRIGHT_PROFILE_SERVICE_SYSTEM_FILES[@]:-}" \
           "${ARCHWRIGHT_PROFILE_SERVICE_USER_FILES[@]:-}"; do
    [[ -z "$f" ]] && continue
    if [[ ! -f "$f" ]]; then
      archwright_warn "profile '${profile}' references a file that does not exist: ${f#"$workspace"/}"
      rc=1
    fi
  done

  return "$rc"
}

# archwright_load_profile <workspace> <profile-name>
# Throwing wrapper for commands that need exactly one valid profile.
archwright_load_profile() {
  local workspace="$1" profile="$2"
  if ! archwright_try_load_profile "$workspace" "$profile"; then
    archwright_die "$EXIT_VALIDATION_ERROR" "profile '${profile}' failed to load, see warnings above"
  fi
}

# --- Asset manifest parsing and validation --------------------------------
#
# See docs/spec/assets-format.md. assets/ is optional; when present,
# assets/manifest/*.conf and assets/payload/ are validated together so a
# manifest pointing at a missing or corrupted payload is a hard error, not
# a silent gap discovered later at converge/restore time.

# archwright_parse_asset_manifest_file <path> -> see archwright_parse_kv_file.
archwright_parse_asset_manifest_file() {
  archwright_parse_kv_file "$1" "$ARCHWRIGHT_ASSET_ALLOWED_KEYS"
}

# archwright_asset_payload_path <workspace> <sha256> -> prints the expected
# content-addressed payload path (does not check it exists).
archwright_asset_payload_path() {
  local workspace="$1" sha="$2"
  printf '%s/assets/payload/%s/%s\n' "$workspace" "${sha:0:2}" "$sha"
}

# archwright_try_load_asset_manifest <workspace> <id>
# Never exits. Returns 0 and populates the ARCHWRIGHT_ASSET_* globals on
# success (grammar + field validity only — does NOT check the payload file;
# archwright_validate_asset_manifests does that once, across all manifests,
# so it can also check for dest_path collisions between manifests).
archwright_try_load_asset_manifest() {
  local workspace="$1" id="$2"
  local file="${workspace}/assets/manifest/${id}.conf"

  if [[ ! "$id" =~ $ARCHWRIGHT_ASSET_ID_PATTERN ]]; then
    archwright_warn "asset id '${id}' does not match ${ARCHWRIGHT_ASSET_ID_PATTERN}"
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    archwright_warn "asset manifest '${id}' not found (expected ${file})"
    return 1
  fi

  local parsed rc=0
  parsed="$(archwright_parse_asset_manifest_file "$file")" || rc=1

  ARCHWRIGHT_ASSET_DEST_CLASS=""
  ARCHWRIGHT_ASSET_DEST_PATH=""
  ARCHWRIGHT_ASSET_PAYLOAD_SHA256=""
  ARCHWRIGHT_ASSET_SIZE=""
  ARCHWRIGHT_ASSET_MODE=""

  local key value
  while IFS=$'\t' read -r key value; do
    [[ -z "$key" ]] && continue
    case "$key" in
      dest_class) ARCHWRIGHT_ASSET_DEST_CLASS="$value" ;;
      dest_path) ARCHWRIGHT_ASSET_DEST_PATH="$value" ;;
      payload_sha256) ARCHWRIGHT_ASSET_PAYLOAD_SHA256="$value" ;;
      size) ARCHWRIGHT_ASSET_SIZE="$value" ;;
      mode) ARCHWRIGHT_ASSET_MODE="$value" ;;
    esac
  done <<< "$parsed"

  local req
  for req in $ARCHWRIGHT_ASSET_REQUIRED_KEYS; do
    case "$req" in
      dest_class) [[ -n "$ARCHWRIGHT_ASSET_DEST_CLASS" ]] || { archwright_warn "asset '${id}' is missing required key 'dest_class'"; rc=1; } ;;
      dest_path) [[ -n "$ARCHWRIGHT_ASSET_DEST_PATH" ]] || { archwright_warn "asset '${id}' is missing required key 'dest_path'"; rc=1; } ;;
      payload_sha256) [[ -n "$ARCHWRIGHT_ASSET_PAYLOAD_SHA256" ]] || { archwright_warn "asset '${id}' is missing required key 'payload_sha256'"; rc=1; } ;;
      size) [[ -n "$ARCHWRIGHT_ASSET_SIZE" ]] || { archwright_warn "asset '${id}' is missing required key 'size'"; rc=1; } ;;
      mode) [[ -n "$ARCHWRIGHT_ASSET_MODE" ]] || { archwright_warn "asset '${id}' is missing required key 'mode'"; rc=1; } ;;
    esac
  done

  if [[ -n "$ARCHWRIGHT_ASSET_DEST_CLASS" && "$ARCHWRIGHT_ASSET_DEST_CLASS" != "home" ]]; then
    archwright_warn "asset '${id}': dest_class '${ARCHWRIGHT_ASSET_DEST_CLASS}' is not supported (only 'home' in spec v0.1)"
    rc=1
  fi
  if [[ -n "$ARCHWRIGHT_ASSET_DEST_PATH" ]]; then
    if [[ "$ARCHWRIGHT_ASSET_DEST_PATH" == /* ]]; then
      archwright_warn "asset '${id}': dest_path must be relative, got '${ARCHWRIGHT_ASSET_DEST_PATH}'"
      rc=1
    fi
    case "/${ARCHWRIGHT_ASSET_DEST_PATH}/" in
      */../*|*/./*)
        archwright_warn "asset '${id}': dest_path must not contain '.' or '..' segments, got '${ARCHWRIGHT_ASSET_DEST_PATH}'"
        rc=1
        ;;
    esac
  fi
  if [[ -n "$ARCHWRIGHT_ASSET_PAYLOAD_SHA256" && ! "$ARCHWRIGHT_ASSET_PAYLOAD_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    archwright_warn "asset '${id}': payload_sha256 is not 64 lowercase hex characters"
    rc=1
  fi
  if [[ -n "$ARCHWRIGHT_ASSET_SIZE" && ! "$ARCHWRIGHT_ASSET_SIZE" =~ ^[0-9]+$ ]]; then
    archwright_warn "asset '${id}': size must be a non-negative base-10 integer, got '${ARCHWRIGHT_ASSET_SIZE}'"
    rc=1
  fi
  if [[ -n "$ARCHWRIGHT_ASSET_MODE" ]]; then
    if [[ ! "$ARCHWRIGHT_ASSET_MODE" =~ ^[0-7]{3,4}$ ]]; then
      archwright_warn "asset '${id}': mode must be 3-4 octal digits, got '${ARCHWRIGHT_ASSET_MODE}'"
      rc=1
    elif [[ "${#ARCHWRIGHT_ASSET_MODE}" -eq 4 && "${ARCHWRIGHT_ASSET_MODE:0:1}" != "0" ]]; then
      archwright_warn "asset '${id}': mode '${ARCHWRIGHT_ASSET_MODE}' sets setuid/setgid/sticky, which is never allowed"
      rc=1
    fi
  fi

  return "$rc"
}

# archwright_validate_asset_manifests <workspace>
# Never exits. Validates assets/ as a whole: every manifest's grammar and
# field rules (via archwright_try_load_asset_manifest), payload presence,
# payload integrity (actual sha256 of the file matches its own name), and
# no two manifests declaring the same dest_class+dest_path. Returns 0 if
# assets/ is absent entirely (nothing to validate) or fully valid.
archwright_validate_asset_manifests() {
  local workspace="$1"
  local assets_dir="${workspace}/assets"

  [[ -d "$assets_dir" ]] || return 0

  local errors=0
  if [[ ! -d "${assets_dir}/manifest" || ! -d "${assets_dir}/payload" ]]; then
    archwright_warn "assets/ exists but assets/manifest/ and assets/payload/ must both be present"
    return 1
  fi

  shopt -s nullglob
  local manifest_files=("${assets_dir}"/manifest/*.conf)
  shopt -u nullglob

  local mf id
  local seen_dests=""
  for mf in "${manifest_files[@]}"; do
    id="$(basename "$mf" .conf)"
    if ! archwright_try_load_asset_manifest "$workspace" "$id"; then
      errors=1
      continue
    fi

    local dest_key="${ARCHWRIGHT_ASSET_DEST_CLASS}:${ARCHWRIGHT_ASSET_DEST_PATH}"
    if printf '%s\n' "$seen_dests" | grep -qxF "$dest_key"; then
      archwright_warn "asset '${id}': dest_path '${ARCHWRIGHT_ASSET_DEST_PATH}' is already declared by another manifest"
      errors=1
    fi
    seen_dests="${seen_dests}${dest_key}"$'\n'

    local payload_path
    payload_path="$(archwright_asset_payload_path "$workspace" "$ARCHWRIGHT_ASSET_PAYLOAD_SHA256")"
    if [[ ! -f "$payload_path" ]]; then
      archwright_warn "asset '${id}': payload missing at ${payload_path#"$workspace"/}"
      errors=1
      continue
    fi
    local actual_sha
    actual_sha="$(sha256sum "$payload_path" | cut -d' ' -f1)"
    if [[ "$actual_sha" != "$ARCHWRIGHT_ASSET_PAYLOAD_SHA256" ]]; then
      archwright_warn "asset '${id}': payload at ${payload_path#"$workspace"/} is corrupted (sha256 mismatch)"
      errors=1
    fi
  done

  return "$errors"
}

# --- Full workspace validation --------------------------------------------

# archwright_validate_workspace <workspace>
# Never exits. Prints findings to stderr, returns 0 if the workspace is
# valid in its entirety (every profile parses, every reference resolves).
archwright_validate_workspace() {
  local workspace="$1"
  local errors=0

  if [[ ! -d "$workspace" ]]; then
    archwright_warn "workspace directory does not exist: ${workspace}"
    return 1
  fi

  local version
  if ! version="$(archwright_read_version_file "$workspace")"; then
    errors=1
  elif [[ ! "$version" =~ ^\^?[0-9]+(\.[0-9]+){0,2}$ ]]; then
    archwright_warn ".archwright-version has an unrecognized format: '${version}' (expected e.g. ^0.1 or 0.1.0)"
    errors=1
  fi

  local dir
  for dir in profiles packages services; do
    if [[ ! -d "${workspace}/${dir}" ]]; then
      archwright_warn "required directory missing: ${dir}/"
      errors=1
    fi
  done
  [[ "$errors" -ne 0 ]] && return 1

  shopt -s nullglob
  local profile_files=("${workspace}"/profiles/*.conf)
  shopt -u nullglob
  if [[ "${#profile_files[@]}" -eq 0 ]]; then
    archwright_warn "no profiles found under profiles/*.conf"
    return 1
  fi

  local pf profile_name
  for pf in "${profile_files[@]}"; do
    profile_name="$(basename "$pf" .conf)"
    archwright_try_load_profile "$workspace" "$profile_name" || errors=1
  done

  archwright_validate_asset_manifests "$workspace" || errors=1

  return "$errors"
}
