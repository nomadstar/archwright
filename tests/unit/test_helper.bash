#!/usr/bin/env bash
# tests/unit/test_helper.bash — loaded by every *.bats file via `load test_helper`.

ARCHWRIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCHWRIGHT_LIB_DIR="${ARCHWRIGHT_ROOT}/lib"
export ARCHWRIGHT_LIB_DIR

# shellcheck source=lib/contract.sh
source "${ARCHWRIGHT_LIB_DIR}/contract.sh"
# shellcheck source=lib/workspace.sh
source "${ARCHWRIGHT_LIB_DIR}/workspace.sh"

FIXTURES_DIR="${ARCHWRIGHT_ROOT}/tests/fixtures/invalid-workspaces"
EXAMPLE_WORKSPACE="${ARCHWRIGHT_ROOT}/examples/minimal-workspace"
