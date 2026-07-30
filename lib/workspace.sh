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
# Two layers are exposed on purpose:
#   archwright_try_load_profile  — never exits, returns 0/1, used by
#                                   `validate` to check every profile and
#                                   report every problem in one pass.
#   archwright_load_profile      — throwing wrapper used by plan/converge/
#                                   drift, which only ever need ONE profile
#                                   and should abort immediately if it is bad.

set -euo pipefail

readonly ARCHWRIGHT_SPEC_VERSION="0"
readonly ARCHWRIGHT_PROFILE_ALLOWED_KEYS="name description packages services_system services_user"
readonly ARCHWRIGHT_PROFILE_REQUIRED_KEYS="name packages"

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

# --- Profile parsing ---------------------------------------------------

# archwright_parse_profile_file <path> -> emits validated `key<TAB>value` lines
# on stdout. Returns non-zero (and warns on stderr) on: unknown key,
# duplicate key, malformed line. Never exits the process.
archwright_parse_profile_file() {
  local file="$1"
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
      archwright_warn "profile parse error at ${file}:${lineno}: expected key=value, got: ${raw}"
      had_error=1
      continue
    fi

    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"

    if ! printf ' %s ' "$ARCHWRIGHT_PROFILE_ALLOWED_KEYS" | grep -qF " ${key} "; then
      archwright_warn "profile parse error at ${file}:${lineno}: unknown key '${key}'"
      had_error=1
      continue
    fi
    if printf ' %s ' "$seen_keys" | grep -qF " ${key} "; then
      archwright_warn "profile parse error at ${file}:${lineno}: duplicate key '${key}'"
      had_error=1
      continue
    fi
    seen_keys="${seen_keys} ${key}"
    printf '%s\t%s\n' "$key" "$value"
  done < "$file"

  return "$had_error"
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

  if [[ -z "$ARCHWRIGHT_PROFILE_NAME" ]]; then
    archwright_warn "profile '${profile}' is missing required key 'name'"
    rc=1
  fi
  if [[ "${#ARCHWRIGHT_PROFILE_PACKAGE_FILES[@]}" -eq 0 ]]; then
    archwright_warn "profile '${profile}' is missing required key 'packages'"
    rc=1
  fi

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

  return "$errors"
}
