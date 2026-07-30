#!/usr/bin/env bats
# Tests for `archwright asset capture` (lib/commands/asset_capture.sh).
# See docs/decisions/0014-declared-assets-and-capture-restore-lifecycle.md
# for the gates being tested here.

load test_helper

# shellcheck source=lib/commands/asset_capture.sh
source "${ARCHWRIGHT_LIB_DIR}/commands/asset_capture.sh"

setup() {
  TEST_HOME="$(mktemp -d)"
  TEST_WS="$(mktemp -d)"
  mkdir -p "$TEST_WS/profiles" "$TEST_WS/packages" "$TEST_WS/services"
  printf '0.1\n' > "$TEST_WS/.archwright-version"
  printf 'tree\n' > "$TEST_WS/packages/official.txt"
  printf 'name=default\npackages=packages/official.txt\n' > "$TEST_WS/profiles/default.conf"
}

teardown() {
  rm -rf "$TEST_HOME" "$TEST_WS"
}

@test "captures a regular file: creates manifest + content-addressed payload, EXIT_CHANGED" {
  mkdir -p "$TEST_HOME/Pictures"
  printf 'hello wallpaper\n' > "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/Pictures/forest.jpg" --workspace "$TEST_WS"
  [ "$status" -eq 2 ]
  [ -f "$TEST_WS/assets/manifest/pictures-forest.jpg.conf" ]
  grep -q 'dest_path=Pictures/forest.jpg' "$TEST_WS/assets/manifest/pictures-forest.jpg.conf"
  grep -q 'mode=0644' "$TEST_WS/assets/manifest/pictures-forest.jpg.conf"
  run archwright_validate_workspace "$TEST_WS"
  [ "$status" -eq 0 ]
}

@test "repeat capture of unchanged content is idempotent: EXIT_OK, manifest untouched" {
  mkdir -p "$TEST_HOME/Pictures"
  printf 'hello wallpaper\n' > "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/Pictures/forest.jpg" --workspace "$TEST_WS"
  [ "$status" -eq 2 ]
  manifest="$TEST_WS/assets/manifest/pictures-forest.jpg.conf"
  before="$(stat -c%Y "$manifest")"
  sleep 1.1
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/Pictures/forest.jpg" --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  after="$(stat -c%Y "$manifest")"
  [ "$before" -eq "$after" ]
}

@test "rejects a symlink as capture input" {
  mkdir -p "$TEST_HOME/Pictures"
  printf 'real content\n' > "$TEST_HOME/Pictures/real.jpg"
  ln -s "$TEST_HOME/Pictures/real.jpg" "$TEST_HOME/Pictures/link.jpg"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/Pictures/link.jpg" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "rejects a path that resolves outside \$HOME" {
  outside="$(mktemp)"
  printf 'not under home\n' > "$outside"
  HOME="$TEST_HOME" run cmd_asset_capture "$outside" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
  rm -f "$outside"
}

@test "rejects a file under ~/.ssh, no override" {
  mkdir -p "$TEST_HOME/.ssh"
  printf 'not a real key\n' > "$TEST_HOME/.ssh/config"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/.ssh/config" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "rejects a file under ~/.gnupg, no override" {
  mkdir -p "$TEST_HOME/.gnupg"
  printf 'not a real keyring\n' > "$TEST_HOME/.gnupg/pubring.kbx"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/.gnupg/pubring.kbx" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "rejects a .env file by name, no override" {
  printf 'SECRET=x\n' > "$TEST_HOME/.env"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/.env" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "rejects an id_rsa-shaped filename, no override" {
  printf 'not a real key\n' > "$TEST_HOME/id_rsa"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/id_rsa" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "rejects a shell history file by name, no override" {
  printf 'ls\ncd /\n' > "$TEST_HOME/.bash_history"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/.bash_history" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "rejects a file over the size limit" {
  head -c 2048 /dev/zero > "$TEST_HOME/big.bin"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/big.bin" --workspace "$TEST_WS" --max-size 1024
  [ "$status" -eq 3 ]
}

@test "--max-size accepts a file that would otherwise exceed the default" {
  head -c 2048 /dev/zero > "$TEST_HOME/big.bin"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/big.bin" --workspace "$TEST_WS" --max-size 4096
  [ "$status" -eq 2 ]
}

@test "rejects an executable file without --allow-executable" {
  printf '#!/bin/sh\necho hi\n' > "$TEST_HOME/script.sh"
  chmod 0755 "$TEST_HOME/script.sh"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/script.sh" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "--allow-executable accepts an executable and preserves its bits in the manifest" {
  printf '#!/bin/sh\necho hi\n' > "$TEST_HOME/script.sh"
  chmod 0755 "$TEST_HOME/script.sh"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/script.sh" --workspace "$TEST_WS" --allow-executable
  [ "$status" -eq 2 ]
  grep -q 'mode=0755' "$TEST_WS/assets/manifest/script.sh.conf"
}

@test "setuid/setgid bits are always stripped, even with --allow-executable" {
  printf '#!/bin/sh\necho hi\n' > "$TEST_HOME/script.sh"
  chmod 4755 "$TEST_HOME/script.sh"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/script.sh" --workspace "$TEST_WS" --allow-executable
  [ "$status" -eq 2 ]
  grep -q 'mode=0755' "$TEST_WS/assets/manifest/script.sh.conf"
  ! grep -q 'mode=4755' "$TEST_WS/assets/manifest/script.sh.conf"
}

@test "same --id with a different source file is rejected, not silently overwritten" {
  printf 'first content\n' > "$TEST_HOME/first.txt"
  printf 'second content\n' > "$TEST_HOME/second.txt"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/first.txt" --workspace "$TEST_WS" --id shared-id
  [ "$status" -eq 2 ]
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/second.txt" --workspace "$TEST_WS" --id shared-id
  [ "$status" -eq 3 ]
}

@test "two different files produce two separate payloads (content-addressed, no collision)" {
  printf 'content A\n' > "$TEST_HOME/a.txt"
  printf 'content B\n' > "$TEST_HOME/b.txt"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/a.txt" --workspace "$TEST_WS"
  [ "$status" -eq 2 ]
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/b.txt" --workspace "$TEST_WS"
  [ "$status" -eq 2 ]
  count="$(find "$TEST_WS/assets/payload" -type f | wc -l)"
  [ "$count" -eq 2 ]
}

@test "identical content captured from two different paths dedups to one payload" {
  printf 'same content\n' > "$TEST_HOME/a.txt"
  printf 'same content\n' > "$TEST_HOME/b.txt"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/a.txt" --workspace "$TEST_WS"
  [ "$status" -eq 2 ]
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/b.txt" --workspace "$TEST_WS"
  [ "$status" -eq 2 ]
  count="$(find "$TEST_WS/assets/payload" -type f | wc -l)"
  [ "$count" -eq 1 ]
}

@test "rejects capturing a directory" {
  mkdir -p "$TEST_HOME/somedir"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/somedir" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "rejects a nonexistent source path" {
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/does-not-exist" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}
