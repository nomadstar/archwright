#!/usr/bin/env bats
# Tests for archwright_parse_profile_file (lib/workspace.sh).
# See docs/spec/profiles-format.md for the grammar being tested.

load test_helper

@test "well-formed profile parses cleanly" {
  run archwright_parse_profile_file "${EXAMPLE_WORKSPACE}/profiles/ci.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'name\tci'* ]]
  [[ "$output" == *$'packages\tpackages/official.txt'* ]]
}

@test "duplicate key is rejected" {
  run archwright_parse_profile_file "${FIXTURES_DIR}/duplicate-key-profile/profiles/default.conf"
  [ "$status" -ne 0 ]
}

@test "unknown key is rejected" {
  run archwright_parse_profile_file "${FIXTURES_DIR}/unknown-key-profile/profiles/default.conf"
  [ "$status" -ne 0 ]
}

@test "line without '=' is rejected" {
  tmp="$(mktemp)"
  printf 'this is not key=value\n' > "$tmp"
  run archwright_parse_profile_file "$tmp"
  [ "$status" -ne 0 ]
  rm -f "$tmp"
}

@test "comments and blank lines are ignored" {
  tmp="$(mktemp)"
  printf '# a comment\n\nname=x\npackages=packages/official.txt\n' > "$tmp"
  run archwright_parse_profile_file "$tmp"
  [ "$status" -eq 0 ]
  rm -f "$tmp"
}
