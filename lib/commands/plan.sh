#!/usr/bin/env bash
# lib/commands/plan.sh — `archwright plan`
#
# Runs the check() stage of every role, in order, and reports what converge
# would do. This command never calls apply() or verify() and never mutates
# the system.
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

cmd_plan() {
  local workspace="$1" profile="$2"
  archwright_load_profile "$workspace" "$profile"

  echo "[archwright] plan for profile '${profile}' — check stage only, no changes will be made"

  local role rc any_changed=0 any_error=0
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
      "$EXIT_CHANGED") any_changed=1 ;;
      *) any_error=1 ;;
    esac
  done

  if [[ "$any_error" -eq 1 ]]; then
    echo "[archwright] plan: one or more roles reported a validation error, see above"
    return "$EXIT_VALIDATION_ERROR"
  elif [[ "$any_changed" -eq 1 ]]; then
    echo "[archwright] plan: changes are pending — 'archwright converge' would apply them"
    return "$EXIT_CHANGED"
  fi
  echo "[archwright] plan: system already matches the declared state"
  return "$EXIT_OK"
}
