#!/usr/bin/env bash
# lib/roles/service.sh — the `service` role.
#
# Manages systemd unit enablement (never start/stop, never disable — see
# docs/decisions/0005-no-automatic-removal.md). System and user units are
# handled separately because they require different systemctl invocations
# and, for user units, a running session bus that may not exist (e.g. in a
# minimal CI container) — that case is reported as `skipped`, not an error.
#
# Calling convention (see lib/contract.sh):
#   role_check  <workspace> --system <file>... --user <file>...
#   role_apply  <workspace> --system <file>... --user <file>...
#   role_verify <workspace> --system <file>... --user <file>...
#
# Either --system or --user may be followed by zero files.

# --- internal helpers --------------------------------------------------

_svc_split_args() {
  # Populates the caller's SYSTEM_FILES / USER_FILES arrays from "$@".
  local mode="system"
  SYSTEM_FILES=()
  USER_FILES=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      --system) mode="system" ;;
      --user) mode="user" ;;
      *) if [[ "$mode" == "system" ]]; then SYSTEM_FILES+=("$arg"); else USER_FILES+=("$arg"); fi ;;
    esac
  done
}

_svc_declared_list() {
  local seen="" file unit
  for file in "$@"; do
    while IFS= read -r unit; do
      if ! printf ' %s ' "$seen" | grep -qF " ${unit} "; then
        seen="${seen} ${unit}"
        printf '%s\n' "$unit"
      fi
    done < <(archwright_read_list_file "$file")
  done
}

_svc_user_bus_available() {
  # Single simple command on purpose (see set -e caveats noted at the top
  # of this file): a reachable session bus can answer a trivial query.
  systemctl --user list-units >/dev/null 2>&1
}

_svc_is_enabled() {
  local scope="$1" unit="$2"
  if [[ "$scope" == "system" ]]; then
    systemctl is-enabled --quiet "$unit" 2>/dev/null
  else
    systemctl --user is-enabled --quiet "$unit" 2>/dev/null
  fi
}

_svc_exists() {
  local scope="$1" unit="$2"
  if [[ "$scope" == "system" ]]; then
    systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -qF "$unit"
  else
    systemctl --user list-unit-files "$unit" --no-legend 2>/dev/null | grep -qF "$unit"
  fi
}

# --- contract ------------------------------------------------------------

role_check() {
  local workspace="$1"; shift
  local SYSTEM_FILES USER_FILES
  _svc_split_args "$@"

  local missing=0 unresolvable=0
  local unit

  local -a declared_system=()
  while IFS= read -r unit; do declared_system+=("$unit"); done < <(_svc_declared_list "${SYSTEM_FILES[@]}")
  for unit in "${declared_system[@]}"; do
    if ! _svc_exists system "$unit"; then
      archwright_log service check "$unit" unresolvable "no such system unit"
      unresolvable=$((unresolvable + 1))
    elif _svc_is_enabled system "$unit"; then
      archwright_log service check "$unit" ok
    else
      archwright_log service check "$unit" missing "system unit disabled"
      missing=$((missing + 1))
    fi
  done

  local user_bus_ok=1
  _svc_user_bus_available && user_bus_ok=0
  local -a declared_user=()
  while IFS= read -r unit; do declared_user+=("$unit"); done < <(_svc_declared_list "${USER_FILES[@]}")
  if [[ "${#declared_user[@]}" -gt 0 && "$user_bus_ok" -ne 0 ]]; then
    archwright_log service check "user-units" skipped "no reachable systemd --user session bus"
  else
    for unit in "${declared_user[@]}"; do
      if ! _svc_exists user "$unit"; then
        archwright_log service check "$unit" unresolvable "no such user unit"
        unresolvable=$((unresolvable + 1))
      elif _svc_is_enabled user "$unit"; then
        archwright_log service check "$unit" ok
      else
        archwright_log service check "$unit" missing "user unit disabled"
        missing=$((missing + 1))
      fi
    done
  fi

  # Informational: enabled but not declared.
  local declared_all
  declared_all="$(printf '%s\n' "${declared_system[@]:-}" "${declared_user[@]:-}")"
  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if ! printf '%s\n' "$declared_all" | grep -qxF "$name"; then
      archwright_log service check "$name" undeclared "enabled system unit, not declared in any profile"
    fi
  done < <(systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}')

  if [[ "$unresolvable" -gt 0 ]]; then
    return "$EXIT_VALIDATION_ERROR"
  elif [[ "$missing" -gt 0 ]]; then
    return "$EXIT_CHANGED"
  fi
  return "$EXIT_OK"
}

role_apply() {
  local workspace="$1"; shift
  local SYSTEM_FILES USER_FILES
  _svc_split_args "$@"

  local unit failed=0

  local -a declared_system=()
  while IFS= read -r unit; do declared_system+=("$unit"); done < <(_svc_declared_list "${SYSTEM_FILES[@]}")
  local -a to_enable_system=()
  for unit in "${declared_system[@]}"; do
    _svc_exists system "$unit" || continue
    _svc_is_enabled system "$unit" && continue
    to_enable_system+=("$unit")
  done
  if [[ "${#to_enable_system[@]}" -gt 0 ]]; then
    if [[ "$(id -u)" -ne 0 ]]; then
      archwright_warn "service role: not running as root, cannot enable system units: ${to_enable_system[*]}"
      failed=1
    elif systemctl enable "${to_enable_system[@]}" >&2; then
      archwright_log service apply "${to_enable_system[*]}" enabled
    else
      archwright_log service apply "${to_enable_system[*]}" failed
      failed=1
    fi
  fi

  local user_bus_ok=1
  _svc_user_bus_available && user_bus_ok=0
  local -a declared_user=()
  while IFS= read -r unit; do declared_user+=("$unit"); done < <(_svc_declared_list "${USER_FILES[@]}")
  if [[ "${#declared_user[@]}" -gt 0 ]]; then
    if [[ "$user_bus_ok" -ne 0 ]]; then
      archwright_log service apply "user-units" skipped "no reachable systemd --user session bus"
    else
      local -a to_enable_user=()
      for unit in "${declared_user[@]}"; do
        _svc_exists user "$unit" || continue
        _svc_is_enabled user "$unit" && continue
        to_enable_user+=("$unit")
      done
      if [[ "${#to_enable_user[@]}" -gt 0 ]]; then
        if systemctl --user enable "${to_enable_user[@]}" >&2; then
          archwright_log service apply "${to_enable_user[*]}" enabled
        else
          archwright_log service apply "${to_enable_user[*]}" failed
          failed=1
        fi
      fi
    fi
  fi

  [[ "$failed" -ne 0 ]] && return "$EXIT_APPLY_FAILED"
  return "$EXIT_CHANGED"
}

role_verify() {
  local workspace="$1"; shift
  local SYSTEM_FILES USER_FILES
  _svc_split_args "$@"

  local unit failures=0

  local -a declared_system=()
  while IFS= read -r unit; do declared_system+=("$unit"); done < <(_svc_declared_list "${SYSTEM_FILES[@]}")
  for unit in "${declared_system[@]}"; do
    _svc_exists system "$unit" || continue
    if _svc_is_enabled system "$unit"; then
      archwright_log service verify "$unit" ok
    else
      archwright_log service verify "$unit" still-disabled
      failures=$((failures + 1))
    fi
  done

  local user_bus_ok=1
  _svc_user_bus_available && user_bus_ok=0
  local -a declared_user=()
  while IFS= read -r unit; do declared_user+=("$unit"); done < <(_svc_declared_list "${USER_FILES[@]}")
  if [[ "${#declared_user[@]}" -gt 0 && "$user_bus_ok" -eq 0 ]]; then
    for unit in "${declared_user[@]}"; do
      _svc_exists user "$unit" || continue
      if _svc_is_enabled user "$unit"; then
        archwright_log service verify "$unit" ok
      else
        archwright_log service verify "$unit" still-disabled
        failures=$((failures + 1))
      fi
    done
  fi

  [[ "$failures" -eq 0 ]] && return "$EXIT_OK"
  return "$EXIT_VERIFY_FAILED"
}
