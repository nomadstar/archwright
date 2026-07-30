#!/usr/bin/env bash
# lib/commands/converge.sh — `archwright converge`
#
# Runs check() for every role; only calls apply() when check() reports
# pending changes; always runs verify() after a successful apply(). Never
# removes packages or disables services (see docs/decisions/0005).
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

cmd_converge() {
  local workspace="$1" profile="$2"
  archwright_load_profile "$workspace" "$profile"

  echo "[archwright] converge for profile '${profile}'"

  local role rc arc vrc
  local has_validation_error=0 has_apply_failed=0 has_verify_failed=0 has_changed=0

  for role in $ARCHWRIGHT_ROLES; do
    echo "[archwright] -- role: ${role} --"

    if archwright_invoke_role "$role" check "$workspace"; then
      rc="$EXIT_OK"
    else
      rc="$?"
    fi
    printf '%s\n' "$ARCHWRIGHT_LAST_OUTPUT"

    if [[ "$rc" != "$EXIT_OK" && "$rc" != "$EXIT_CHANGED" ]]; then
      echo "[archwright] role '${role}': check reported a validation error, skipping apply"
      has_validation_error=1
      continue
    fi
    if [[ "$rc" == "$EXIT_OK" ]]; then
      echo "[archwright] role '${role}': already conforms to spec, apply skipped"
      continue
    fi

    # rc == EXIT_CHANGED: apply, then verify.
    if archwright_invoke_role "$role" apply "$workspace"; then
      arc="$EXIT_OK"
    else
      arc="$?"
    fi
    printf '%s\n' "$ARCHWRIGHT_LAST_OUTPUT"

    if [[ "$arc" != "$EXIT_OK" && "$arc" != "$EXIT_CHANGED" ]]; then
      echo "[archwright] role '${role}': apply failed"
      has_apply_failed=1
      continue
    fi
    has_changed=1

    if archwright_invoke_role "$role" verify "$workspace"; then
      vrc="$EXIT_OK"
    else
      vrc="$?"
    fi
    printf '%s\n' "$ARCHWRIGHT_LAST_OUTPUT"

    if [[ "$vrc" != "$EXIT_OK" ]]; then
      echo "[archwright] role '${role}': verify failed after apply"
      has_verify_failed=1
    else
      echo "[archwright] role '${role}': converged and verified"
    fi
  done

  if [[ "$has_validation_error" -eq 1 ]]; then
    return "$EXIT_VALIDATION_ERROR"
  elif [[ "$has_apply_failed" -eq 1 ]]; then
    return "$EXIT_APPLY_FAILED"
  elif [[ "$has_verify_failed" -eq 1 ]]; then
    return "$EXIT_VERIFY_FAILED"
  elif [[ "$has_changed" -eq 1 ]]; then
    return "$EXIT_CHANGED"
  fi
  return "$EXIT_OK"
}
