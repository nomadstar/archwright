#!/usr/bin/env bats
# Tests for `archwright asset scan` and `archwright asset list`
# (lib/commands/asset_scan.sh, lib/commands/asset_list.sh).

load test_helper

# shellcheck source=lib/commands/asset_capture.sh
source "${ARCHWRIGHT_LIB_DIR}/commands/asset_capture.sh"
# shellcheck source=lib/commands/asset_scan.sh
source "${ARCHWRIGHT_LIB_DIR}/commands/asset_scan.sh"
# shellcheck source=lib/commands/asset_list.sh
source "${ARCHWRIGHT_LIB_DIR}/commands/asset_list.sh"

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

@test "scan reports a referenced (not-yet-declared) file" {
  mkdir -p "$TEST_HOME/Pictures"
  printf 'wallpaper bytes\n' > "$TEST_HOME/Pictures/forest.jpg"
  printf 'exec ~/Pictures/forest.jpg\n' > "$TEST_HOME/config"
  HOME="$TEST_HOME" run cmd_asset_scan "$TEST_HOME/config" --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=${TEST_HOME}/Pictures/forest.jpg status=referenced"* ]]
}

@test "scan reports a declared file once it has been captured" {
  mkdir -p "$TEST_HOME/Pictures"
  printf 'wallpaper bytes\n' > "$TEST_HOME/Pictures/forest.jpg"
  printf 'exec ~/Pictures/forest.jpg\n' > "$TEST_HOME/config"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/Pictures/forest.jpg" --workspace "$TEST_WS"
  [ "$status" -eq 2 ]
  HOME="$TEST_HOME" run cmd_asset_scan "$TEST_HOME/config" --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=${TEST_HOME}/Pictures/forest.jpg status=declared"* ]]
}

@test "scan reports a dangling (missing) reference" {
  printf 'exec ~/Pictures/does-not-exist.jpg\n' > "$TEST_HOME/config"
  HOME="$TEST_HOME" run cmd_asset_scan "$TEST_HOME/config" --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=${TEST_HOME}/Pictures/does-not-exist.jpg status=missing"* ]]
}

@test "scan reports a shell-variable reference as unparsed, not missing" {
  printf 'exec $XDG_PICTURES_DIR/random.jpg\n' > "$TEST_HOME/config"
  HOME="$TEST_HOME" run cmd_asset_scan "$TEST_HOME/config" --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *'item=$XDG_PICTURES_DIR/random.jpg status=unparsed'* ]]
  [[ "$output" != *'status=missing'* ]]
}

@test "scan reports a glob reference as unparsed, not missing" {
  printf 'exec ~/Pictures/wallpapers/*.png\n' > "$TEST_HOME/config"
  HOME="$TEST_HOME" run cmd_asset_scan "$TEST_HOME/config" --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *'item=~/Pictures/wallpapers/*.png status=unparsed'* ]]
}

@test "scan never runs with zero explicit inputs" {
  run cmd_asset_scan --workspace "$TEST_WS"
  [ "$status" -ne 0 ]
}

@test "scan rejects a nonexistent input file with EXIT_UNEXPECTED" {
  HOME="$TEST_HOME" run cmd_asset_scan "$TEST_HOME/does-not-exist" --workspace "$TEST_WS"
  [ "$status" -eq 1 ]
}

@test "scan on a broken assets/ fails with EXIT_VALIDATION_ERROR" {
  mkdir -p "$TEST_WS/assets/manifest"
  cat > "$TEST_WS/assets/manifest/broken.conf" <<'EOF'
dest_class=xdg_config
dest_path=x
payload_sha256=deadbeef
size=1
mode=0644
EOF
  printf 'exec ~/Pictures/forest.jpg\n' > "$TEST_HOME/config"
  HOME="$TEST_HOME" run cmd_asset_scan "$TEST_HOME/config" --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "scan recurses into a directory input" {
  mkdir -p "$TEST_HOME/configs/sub"
  printf 'exec ~/Pictures/forest.jpg\n' > "$TEST_HOME/configs/a"
  printf 'exec ~/Pictures/other.jpg\n' > "$TEST_HOME/configs/sub/b"
  HOME="$TEST_HOME" run cmd_asset_scan "$TEST_HOME/configs" --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"forest.jpg"* ]]
  [[ "$output" == *"other.jpg"* ]]
}

@test "list reports nothing declared on a workspace with no assets/" {
  run cmd_asset_list --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no assets declared"* ]]
}

@test "list reports every declared asset with its fields" {
  mkdir -p "$TEST_HOME/Pictures"
  printf 'wallpaper bytes\n' > "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/Pictures/forest.jpg" --workspace "$TEST_WS"
  [ "$status" -eq 2 ]
  run cmd_asset_list --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=pictures-forest.jpg status=declared"* ]]
  [[ "$output" == *"dest=Pictures/forest.jpg"* ]]
}

@test "list fails with EXIT_VALIDATION_ERROR on a corrupted payload" {
  mkdir -p "$TEST_HOME/Pictures"
  printf 'wallpaper bytes\n' > "$TEST_HOME/Pictures/forest.jpg"
  HOME="$TEST_HOME" run cmd_asset_capture "$TEST_HOME/Pictures/forest.jpg" --workspace "$TEST_WS"
  [ "$status" -eq 2 ]
  payload="$(find "$TEST_WS/assets/payload" -type f | head -n1)"
  printf 'corrupted' > "$payload"
  run cmd_asset_list --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}
