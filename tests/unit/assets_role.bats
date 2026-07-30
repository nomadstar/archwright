#!/usr/bin/env bats
# Tests for the `assets` role (lib/roles/assets.sh) — the workspace ->
# system direction (restore). Unlike package/service, this role touches
# only $HOME, not pacman/systemctl, so it can be exercised directly here
# rather than only in the container-based integration test.

load test_helper

# shellcheck source=lib/commands/asset_capture.sh
source "${ARCHWRIGHT_LIB_DIR}/commands/asset_capture.sh"
# shellcheck source=lib/roles/assets.sh
source "${ARCHWRIGHT_LIB_DIR}/roles/assets.sh"

setup() {
  TEST_HOME="$(mktemp -d)"
  TEST_WS="$(mktemp -d)"
  mkdir -p "$TEST_HOME/Pictures"
  printf 'wallpaper bytes\n' > "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" cmd_asset_capture "$TEST_HOME/Pictures/forest.jpg" --workspace "$TEST_WS" --id forest >/dev/null || true
}

teardown() {
  rm -rf "$TEST_HOME" "$TEST_WS"
}

@test "check reports missing when the destination doesn't exist yet" {
  rm -f "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run role_check "$TEST_WS"
  [ "$status" -eq 2 ]
  [[ "$output" == *"item=forest status=missing"* ]]
}

@test "check reports ok when the destination already matches" {
  HOME="$TEST_HOME" run role_check "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=forest status=ok"* ]]
}

@test "check reports modified when content at the destination diverges" {
  printf 'tampered content\n' > "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run role_check "$TEST_WS"
  [ "$status" -eq 2 ]
  [[ "$output" == *"item=forest status=modified"* ]]
}

@test "check reports modified when only the mode diverges" {
  chmod 0600 "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run role_check "$TEST_WS"
  [ "$status" -eq 2 ]
  [[ "$output" == *"item=forest status=modified"* ]]
}

@test "apply restores a missing destination from the payload" {
  rm -f "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run role_apply "$TEST_WS"
  [ "$status" -eq 2 ]
  [ -f "$TEST_HOME/Pictures/forest.jpg" ]
  [ "$(cat "$TEST_HOME/Pictures/forest.jpg")" = "wallpaper bytes" ]
}

@test "apply fixes mode without needing to re-copy content" {
  chmod 0600 "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run role_apply "$TEST_WS"
  [ "$status" -eq 2 ]
  mode="$(stat -c%a "$TEST_HOME/Pictures/forest.jpg")"
  [ "$mode" = "644" ]
}

@test "apply refuses to overwrite a symlink at the destination" {
  rm -f "$TEST_HOME/Pictures/forest.jpg"
  ln -s /nonexistent "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run role_apply "$TEST_WS"
  [ "$status" -eq 4 ]
}

@test "verify passes when the destination matches the manifest" {
  HOME="$TEST_HOME" run role_verify "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=forest status=ok"* ]]
}

@test "verify fails when the destination is missing" {
  rm -f "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run role_verify "$TEST_WS"
  [ "$status" -eq 5 ]
  [[ "$output" == *"item=forest status=still-missing"* ]]
}

@test "full check -> apply -> verify cycle is idempotent on a second run" {
  rm -f "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run role_check "$TEST_WS"
  [ "$status" -eq 2 ]
  HOME="$TEST_HOME" run role_apply "$TEST_WS"
  [ "$status" -eq 2 ]
  HOME="$TEST_HOME" run role_verify "$TEST_WS"
  [ "$status" -eq 0 ]

  # Second pass: check must now report EXIT_OK (nothing pending), matching
  # the same idempotency contract package/service already prove in the
  # container-based integration test.
  HOME="$TEST_HOME" run role_check "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=forest status=ok"* ]]
}

@test "converge (assets role wired via _common.sh) restores the example workspace's asset idempotently" {
  load test_helper
  # shellcheck source=lib/commands/_common.sh
  source "${ARCHWRIGHT_LIB_DIR}/commands/_common.sh"
  # shellcheck source=lib/commands/converge.sh
  source "${ARCHWRIGHT_LIB_DIR}/commands/converge.sh"
  archwright_load_profile "$EXAMPLE_WORKSPACE" ci

  fake_home="$(mktemp -d)"
  HOME="$fake_home" run cmd_converge "$EXAMPLE_WORKSPACE" ci
  [[ "$output" == *"role=assets action=apply item=example-note status=restored"* ]]
  [ -f "$fake_home/.local/share/archwright-example/note.txt" ]

  HOME="$fake_home" run archwright_invoke_role assets check "$EXAMPLE_WORKSPACE"
  [ "$status" -eq 0 ]
  rm -rf "$fake_home"
}
