#!/usr/bin/env bats
# Tests for archwright_read_list_file (lib/contract.sh).

load test_helper

@test "strips full-line comments and blank lines" {
  tmp="$(mktemp)"
  printf '# comment\n\ntree\n\nopenssh\n' > "$tmp"
  run archwright_read_list_file "$tmp"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "tree" ]
  [ "${lines[1]}" = "openssh" ]
  rm -f "$tmp"
}

@test "strips inline comments and trailing whitespace" {
  tmp="$(mktemp)"
  printf 'tree   # installed for the docs example\n' > "$tmp"
  run archwright_read_list_file "$tmp"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "tree" ]
  rm -f "$tmp"
}

@test "trims leading and trailing whitespace" {
  tmp="$(mktemp)"
  printf '   tree   \n' > "$tmp"
  run archwright_read_list_file "$tmp"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "tree" ]
  rm -f "$tmp"
}

@test "missing file yields no output, not an error" {
  run archwright_read_list_file "/nonexistent/path/should/not/exist.txt"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 0 ]
}

@test "example workspace packages file parses to exactly tree and openssh" {
  run archwright_read_list_file "${EXAMPLE_WORKSPACE}/packages/official.txt"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "tree" ]
  [ "${lines[1]}" = "openssh" ]
  [ "${#lines[@]}" -eq 2 ]
}
