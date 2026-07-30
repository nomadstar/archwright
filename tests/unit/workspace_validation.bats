#!/usr/bin/env bats
# Tests for archwright_validate_workspace (lib/workspace.sh), against the
# bundled example workspace (must pass) and every fixture under
# tests/fixtures/invalid-workspaces/ (each must fail — see that
# directory's README.md for what each one is testing).

load test_helper

@test "minimal-workspace validates successfully" {
  run archwright_validate_workspace "$EXAMPLE_WORKSPACE"
  [ "$status" -eq 0 ]
}

@test "missing-version fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/missing-version"
  [ "$status" -ne 0 ]
}

@test "missing-required-dirs fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/missing-required-dirs"
  [ "$status" -ne 0 ]
}

@test "no-profiles fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/no-profiles"
  [ "$status" -ne 0 ]
}

@test "duplicate-key-profile fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/duplicate-key-profile"
  [ "$status" -ne 0 ]
}

@test "dangling-reference fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/dangling-reference"
  [ "$status" -ne 0 ]
}

@test "unknown-key-profile fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/unknown-key-profile"
  [ "$status" -ne 0 ]
}

@test "missing-required-key fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/missing-required-key"
  [ "$status" -ne 0 ]
}

@test "nonexistent workspace directory fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/this-directory-does-not-exist"
  [ "$status" -ne 0 ]
}
