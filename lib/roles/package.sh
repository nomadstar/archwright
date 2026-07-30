#!/usr/bin/env bash
# lib/roles/package.sh — the `package` role.
#
# Manages official-repo packages via pacman. Does NOT touch AUR/foreign
# packages in this version (see docs/decisions/0004-no-aur-role-yet.md).
#
# Calling convention (see lib/contract.sh):
#   role_check  <workspace> <declared-file>...
#   role_apply  <workspace> <declared-file>...
#   role_verify <workspace> <declared-file>...
#
# Every <declared-file> is a plain list file (see docs/spec/packages-format.md),
# already resolved to an absolute path by lib/workspace.sh.

# --- internal helpers --------------------------------------------------

_pkg_declared_list() {
  # Reads all declared-file args, dedupes, preserves first-seen order.
  local seen="" file pkg
  for file in "$@"; do
    while IFS= read -r pkg; do
      if ! printf ' %s ' "$seen" | grep -qF " ${pkg} "; then
        seen="${seen} ${pkg}"
        printf '%s\n' "$pkg"
      fi
    done < <(archwright_read_list_file "$file")
  done
}

_pkg_is_installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

_pkg_is_official() {
  # Resolvable in a sync (official repo) database, as opposed to AUR/foreign.
  pacman -Si "$1" >/dev/null 2>&1
}

# --- contract ------------------------------------------------------------

role_check() {
  local workspace="$1"; shift
  local -a declared=()
  local pkg
  while IFS= read -r pkg; do declared+=("$pkg"); done < <(_pkg_declared_list "$@")

  local missing=0 unresolvable=0
  for pkg in "${declared[@]}"; do
    if _pkg_is_installed "$pkg"; then
      archwright_log package check "$pkg" ok
    elif _pkg_is_official "$pkg"; then
      archwright_log package check "$pkg" missing "not installed, resolvable in an official repo"
      missing=$((missing + 1))
    else
      archwright_log package check "$pkg" unresolvable "not installed and not found in any official repo (AUR packages are not managed by this role yet)"
      unresolvable=$((unresolvable + 1))
    fi
  done

  # Informational only: explicitly installed but not declared anywhere.
  local explicit_official explicit_foreign
  explicit_official="$(pacman -Qqen 2>/dev/null || true)"
  explicit_foreign="$(pacman -Qqem 2>/dev/null || true)"
  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if ! printf '%s\n' "${declared[@]:-}" | grep -qxF "$name"; then
      archwright_log package check "$name" undeclared "explicitly installed (official repo), not declared in any packages file"
    fi
  done <<< "$explicit_official"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if ! printf '%s\n' "${declared[@]:-}" | grep -qxF "$name"; then
      archwright_log package check "$name" undeclared-foreign "explicitly installed (AUR/foreign), not declared — out of scope for this role"
    fi
  done <<< "$explicit_foreign"

  if [[ "$unresolvable" -gt 0 ]]; then
    return "$EXIT_VALIDATION_ERROR"
  elif [[ "$missing" -gt 0 ]]; then
    return "$EXIT_CHANGED"
  fi
  return "$EXIT_OK"
}

role_apply() {
  local workspace="$1"; shift
  local -a declared=() to_install=()
  local pkg
  while IFS= read -r pkg; do declared+=("$pkg"); done < <(_pkg_declared_list "$@")

  for pkg in "${declared[@]}"; do
    if ! _pkg_is_installed "$pkg" && _pkg_is_official "$pkg"; then
      to_install+=("$pkg")
    fi
  done

  if [[ "${#to_install[@]}" -eq 0 ]]; then
    return "$EXIT_OK"
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    archwright_warn "package role: not running as root, cannot pacman -S: ${to_install[*]}"
    return "$EXIT_APPLY_FAILED"
  fi

  archwright_log package apply "${to_install[*]}" installing
  if ! pacman -S --needed --noconfirm "${to_install[@]}" >&2; then
    archwright_log package apply "${to_install[*]}" failed
    return "$EXIT_APPLY_FAILED"
  fi
  archwright_log package apply "${to_install[*]}" installed
  return "$EXIT_CHANGED"
}

role_verify() {
  local workspace="$1"; shift
  local -a declared=()
  local pkg
  while IFS= read -r pkg; do declared+=("$pkg"); done < <(_pkg_declared_list "$@")

  local failures=0
  for pkg in "${declared[@]}"; do
    if _pkg_is_official "$pkg" || _pkg_is_installed "$pkg"; then
      if _pkg_is_installed "$pkg"; then
        archwright_log package verify "$pkg" ok
      else
        archwright_log package verify "$pkg" still-missing
        failures=$((failures + 1))
      fi
    fi
    # Unresolvable packages were already reported by check(); verify does
    # not re-flag them as failures here since apply() never attempted them.
  done

  [[ "$failures" -eq 0 ]] && return "$EXIT_OK"
  return "$EXIT_VERIFY_FAILED"
}
