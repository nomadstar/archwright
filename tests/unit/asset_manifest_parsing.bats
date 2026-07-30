#!/usr/bin/env bats
# Tests for archwright_parse_asset_manifest_file, archwright_try_load_asset_manifest,
# and archwright_validate_asset_manifests (lib/workspace.sh).
# See docs/spec/assets-format.md for the grammar being tested.

load test_helper

GOOD_SHA="68f4d80c53ffd90cc0f2203a288ebfda791c142616a38782592c911c56217dca"

@test "well-formed asset manifest parses cleanly" {
  run archwright_parse_asset_manifest_file "${EXAMPLE_WORKSPACE}/assets/manifest/example-note.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'dest_class\thome'* ]]
  [[ "$output" == *$'dest_path\t.local/share/archwright-example/note.txt'* ]]
}

@test "shared kv parser rejects unknown keys the same way for profiles and assets" {
  run archwright_parse_asset_manifest_file "${FIXTURES_DIR}/asset-unknown-key/assets/manifest/x.conf"
  [ "$status" -ne 0 ]
}

@test "example workspace validates with its asset manifest present" {
  run archwright_validate_workspace "$EXAMPLE_WORKSPACE"
  [ "$status" -eq 0 ]
}

@test "example asset manifest loads with correct fields" {
  archwright_try_load_asset_manifest "$EXAMPLE_WORKSPACE" example-note
  [ "$ARCHWRIGHT_ASSET_DEST_CLASS" = "home" ]
  [ "$ARCHWRIGHT_ASSET_DEST_PATH" = ".local/share/archwright-example/note.txt" ]
  [ "$ARCHWRIGHT_ASSET_MODE" = "0644" ]
}

@test "missing assets/payload/ fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-missing-payload-dir"
  [ "$status" -ne 0 ]
}

@test "unknown key in asset manifest fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-unknown-key"
  [ "$status" -ne 0 ]
}

@test "duplicate key in asset manifest fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-duplicate-key"
  [ "$status" -ne 0 ]
}

@test "missing required key in asset manifest fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-missing-required-key"
  [ "$status" -ne 0 ]
}

@test "dest_class other than home fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-bad-dest-class"
  [ "$status" -ne 0 ]
}

@test "path traversal in dest_path fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-path-traversal"
  [ "$status" -ne 0 ]
}

@test "malformed payload_sha256 fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-bad-sha256"
  [ "$status" -ne 0 ]
}

@test "non-numeric size fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-bad-size"
  [ "$status" -ne 0 ]
}

@test "setuid bit in mode fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-setuid-mode"
  [ "$status" -ne 0 ]
}

@test "missing payload file fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-missing-payload"
  [ "$status" -ne 0 ]
}

@test "corrupted payload (hash mismatch) fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-corrupted-payload"
  [ "$status" -ne 0 ]
}

@test "two manifests declaring the same dest_path fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-duplicate-dest-path"
  [ "$status" -ne 0 ]
}

@test "invalid asset id (uppercase) fails validation" {
  run archwright_validate_workspace "${FIXTURES_DIR}/asset-invalid-id"
  [ "$status" -ne 0 ]
}

@test "workspace with no assets/ directory at all is still valid" {
  # dangling-reference already fails for an unrelated reason; use a fixture
  # that has no assets/ dir and is otherwise valid to prove assets/ is
  # genuinely optional, not just "happens to be absent in fixtures that
  # fail for other reasons."
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/profiles" "$tmp/packages" "$tmp/services"
  printf '0.1\n' > "$tmp/.archwright-version"
  printf 'tree\n' > "$tmp/packages/official.txt"
  printf 'name=default\npackages=packages/official.txt\n' > "$tmp/profiles/default.conf"
  run archwright_validate_workspace "$tmp"
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
}
