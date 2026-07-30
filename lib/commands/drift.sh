#!/usr/bin/env bash
# lib/commands/drift.sh — `archwright drift`
#
# Report-only. Runs check() for every role and additionally flags
# "undeclared" findings (things present on the system but not declared
# anywhere) as drift, even though those don't make check() itself return
# EXIT_CHANGED. Never calls apply() or verify(); never mutates the system.
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

cmd_drift() {
  local workspace="$1" profile="$2"
  archwright_load_profile "$workspace" "$profile"

  echo "[archwright] drift report for profile '${profile}' — report only, no changes will be made"

  local role rc has_error=0 has_drift=0
  for role in $ARCHWRIGHT_ROLES; do
    echo "[archwright] -- role: ${role} --"
    if archwright_invoke_role "$role" check "$workspace"; then
      rc="$EXIT_OK"
    else
      rc="$?"
    fi
    printf '%s\n' "$ARCHWRIGHT_LAST_OUTPUT"

    case "$rc" in
      "$EXIT_OK") : ;;
      "$EXIT_CHANGED") has_drift=1 ;;
      *) has_error=1 ;;
    esac
    if printf '%s\n' "$ARCHWRIGHT_LAST_OUTPUT" | grep -q 'status=undeclared'; then
      has_drift=1
    fi
  done

  if [[ "$has_error" -eq 1 ]]; then
    echo "[archwright] drift: workspace has unresolved references, see above"
    return "$EXIT_VALIDATION_ERROR"
  elif [[ "$has_drift" -eq 1 ]]; then
    echo "[archwright] drift: divergence detected between declared and real state"
    return "$EXIT_CHANGED"
  fi
  echo "[archwright] drift: no divergence detected"
  return "$EXIT_OK"
}
