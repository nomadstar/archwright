#!/usr/bin/env bash
# tests/integration/idempotency.sh
#
# Proves the one property this project's first release exists to
# demonstrate (see docs/architecture.md): a second `archwright converge`
# over an already-converged workspace makes no changes.
#
# Intended to run as root inside an ephemeral Arch Linux container — see
# docs/testing.md for how to run this locally and what CI does with it.
# Mutates the container's package/service state; never run this against a
# real machine you care about.
#
# Deliberately does NOT `set -e`: every step below needs to capture and
# assert on a specific exit code rather than abort at the first non-zero
# status, since EXIT_CHANGED (2) is an expected, successful outcome for
# several of these steps.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE="${ROOT}/examples/minimal-workspace"
ARCHWRIGHT="${ROOT}/bin/archwright"
PROFILE="ci"

fail() { echo "FAIL: $*" >&2; exit 1; }
info() { echo "== $*"; }
assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" -ne "$expected" ]]; then
    fail "${desc}: expected exit ${expected}, got ${actual}"
  fi
  info "${desc}: exit ${actual} (expected)"
}

[[ "$(id -u)" -eq 0 ]] || fail "this test must run as root (it installs packages and enables units)"
command -v pacman >/dev/null 2>&1 || fail "pacman not found — this must run inside an Arch container"

info "syncing pacman databases (pacman -Syu, not -Sy, to avoid a partial upgrade)"
pacman -Syu --noconfirm >/dev/null 2>&1 || fail "pacman -Syu failed"

info "step 1/5: archwright validate"
"$ARCHWRIGHT" validate --workspace "$WORKSPACE"
assert_exit "validate" 0 "$?"

info "step 2/5: archwright plan (first run — container is fresh, changes must be pending)"
"$ARCHWRIGHT" plan --workspace "$WORKSPACE" --profile "$PROFILE"
assert_exit "first plan" 2 "$?"

info "step 3/5: archwright converge (first run — applies the pending changes)"
"$ARCHWRIGHT" converge --workspace "$WORKSPACE" --profile "$PROFILE"
rc=$?
if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then
  fail "first converge: expected exit 0 or 2 (success, with or without changes), got ${rc}"
fi
info "first converge: exit ${rc} (expected 0 or 2)"

info "step 4/5: archwright converge (SECOND run — this is the property under test)"
"$ARCHWRIGHT" converge --workspace "$WORKSPACE" --profile "$PROFILE"
assert_exit "second converge (idempotency claim)" 0 "$?"

info "step 5/5: archwright drift (report-only; a base container legitimately has"
info "  other explicit packages/enabled units beyond this workspace's declarations,"
info "  so we only assert drift ran cleanly, not that it found zero divergence)"
"$ARCHWRIGHT" drift --workspace "$WORKSPACE" --profile "$PROFILE"
rc=$?
if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then
  fail "drift: expected exit 0 or 2 (report ran cleanly), got ${rc} (3 would mean an unresolved reference — a real bug)"
fi
info "drift: exit ${rc} (expected 0 or 2)"

info "all idempotency assertions passed"
