#!/usr/bin/env bats
# Tests for `archwright workspace publish` (lib/commands/workspace_publish.sh)
# against lib/providers/mock.sh — a real (file://) but non-network provider,
# so these exercise the real git plumbing in lib/git.sh end-to-end without
# ever touching GitHub/GitLab. See docs/decisions/0015-private-git-provider-publication.md
# for the ten-step order and state machine being tested here.

load test_helper

# shellcheck source=lib/commands/workspace_publish.sh
source "${ARCHWRIGHT_LIB_DIR}/commands/workspace_publish.sh"

setup() {
  MOCK_HOME="$(mktemp -d)"
  TEST_WS="$(mktemp -d)"
  mkdir -p "$TEST_WS/profiles" "$TEST_WS/packages" "$TEST_WS/services"
  printf '0.1\n' > "$TEST_WS/.archwright-version"
  printf 'tree\n' > "$TEST_WS/packages/official.txt"
  printf 'name=default\npackages=packages/official.txt\n' > "$TEST_WS/profiles/default.conf"
}

teardown() {
  rm -rf "$MOCK_HOME" "$TEST_WS"
}

_git_init_committed() {
  git -C "$TEST_WS" init -q
  git -C "$TEST_WS" -c user.email=test@invalidhost -c user.name=t add -A
  git -C "$TEST_WS" -c user.email=test@invalidhost -c user.name=t commit -q -m "initial"
}

_authenticate_mock() {
  touch "$MOCK_HOME/auth"
  echo "testuser" > "$MOCK_HOME/identity"
}

@test "fails (no fallback) when the provider is unknown" {
  run cmd_workspace_publish --provider does-not-exist --workspace "$TEST_WS"
  [ "$status" -eq 1 ]
}

@test "fails when there is no git repository at all" {
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "fails when the git repository has no commits yet" {
  git -C "$TEST_WS" init -q
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "fails on a dirty working tree, never stages or commits" {
  _git_init_committed
  printf 'uncommitted\n' >> "$TEST_WS/profiles/default.conf"
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
  # never committed on our behalf:
  run git -C "$TEST_WS" status --porcelain
  [ -n "$output" ]
}

@test "fails when the provider is not authenticated, without trying another provider" {
  _git_init_committed
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "fails when the provider is unavailable (ARCHWRIGHT_MOCK_PROVIDER_HOME unset)" {
  _git_init_committed
  _authenticate_mock
  run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "creates a private repo when it's absent, then pushes" {
  _git_init_committed
  _authenticate_mock
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=repo status=created"* ]]
  [[ "$output" == *"item=push status=ok"* ]]
  [[ "$output" == *"item=published status=ok"* ]]
}

@test "second publish reuses the already-existing repo, no recreation" {
  _git_init_committed
  _authenticate_mock
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=repo status=exists"* ]]
}

@test "refuses to push into a pre-existing repo that isn't private" {
  _git_init_committed
  _authenticate_mock
  repo="$(basename "$TEST_WS")"
  mkdir -p "$MOCK_HOME/repos/testuser"
  git init --bare -q "$MOCK_HOME/repos/testuser/${repo}.git"
  echo "public" > "$MOCK_HOME/repos/testuser/${repo}.visibility"
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}

@test "configures the remote under the provider's name, not 'origin'" {
  _git_init_committed
  _authenticate_mock
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  run git -C "$TEST_WS" remote
  [[ "$output" == *"mock"* ]]
  [[ "$output" != *"origin"* ]]
}

@test "reuses an already-correct remote without reconfiguring it" {
  _git_init_committed
  _authenticate_mock
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=remote status=ok"* ]]
}

@test "refuses to replace a remote that already points somewhere else (no --force exists)" {
  _git_init_committed
  _authenticate_mock
  git -C "$TEST_WS" remote add mock "https://example.invalid/somewhere/else.git"
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
  run git -C "$TEST_WS" remote get-url mock
  [ "$output" = "https://example.invalid/somewhere/else.git" ]
}

@test "--remote lets the same workspace publish to a second target under a different name" {
  _git_init_committed
  _authenticate_mock
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS" --remote mock-mirror --repo "$(basename "$TEST_WS")-mirror"
  [ "$status" -eq 0 ]
  run git -C "$TEST_WS" remote
  [[ "$output" == *"mock"* ]]
  [[ "$output" == *"mock-mirror"* ]]
}

@test "resumes cleanly after an interruption between repo creation and remote configuration" {
  _git_init_committed
  _authenticate_mock
  repo="$(basename "$TEST_WS")"
  # Simulate step 7 having already completed (repo created) on a prior,
  # interrupted run, but step 8 (remote configuration) never having run.
  mkdir -p "$MOCK_HOME/repos/testuser"
  git init --bare -q "$MOCK_HOME/repos/testuser/${repo}.git"
  echo "private" > "$MOCK_HOME/repos/testuser/${repo}.visibility"
  run git -C "$TEST_WS" remote get-url mock
  [ "$status" -ne 0 ]  # confirm remote is NOT configured yet, matching the interrupted state

  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=repo status=exists"* ]]
  [[ "$output" == *"item=remote status=configured"* ]]
  [[ "$output" == *"item=published status=ok"* ]]
}

@test "resumes cleanly after an interruption between remote configuration and push" {
  _git_init_committed
  _authenticate_mock
  repo="$(basename "$TEST_WS")"
  mkdir -p "$MOCK_HOME/repos/testuser"
  git init --bare -q "$MOCK_HOME/repos/testuser/${repo}.git"
  echo "private" > "$MOCK_HOME/repos/testuser/${repo}.visibility"
  # Simulate step 8 having already completed too, but no push yet.
  git -C "$TEST_WS" remote add mock "file://${MOCK_HOME}/repos/testuser/${repo}.git"

  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item=remote status=ok"* ]]
  [[ "$output" == *"item=push status=ok"* ]]
}

@test "published content is byte-for-byte retrievable from the mock remote" {
  _git_init_committed
  _authenticate_mock
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 0 ]
  repo="$(basename "$TEST_WS")"
  clone_dir="$(mktemp -d)"
  git clone -q "file://${MOCK_HOME}/repos/testuser/${repo}.git" "$clone_dir"
  diff -r "$TEST_WS/profiles" "$clone_dir/profiles"
  rm -rf "$clone_dir"
}

@test "fails the whole run if the workspace itself doesn't validate" {
  rm -rf "$TEST_WS/packages"
  _git_init_committed
  _authenticate_mock
  ARCHWRIGHT_MOCK_PROVIDER_HOME="$MOCK_HOME" run cmd_workspace_publish --provider mock --workspace "$TEST_WS"
  [ "$status" -eq 3 ]
}
