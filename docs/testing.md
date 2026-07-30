# Testing

Two layers, matching what the implementation brief asked for: fast unit
tests that need no root and no real system mutation, and one integration
test that proves the idempotency claim against a real (containerized) Arch
system.

## Unit tests

**Requires:** bash ≥ 4.4, `bats` (`pacman -S bats`). No root, no network,
no package/service mutation — these test the parser and validator only.

```sh
bats tests/unit/
```

What they cover:

- `tests/unit/workspace_validation.bats` — `archwright_validate_workspace`
  against `examples/minimal-workspace` (must pass) and every fixture under
  `tests/fixtures/invalid-workspaces/` (each must fail, for the specific
  reason its directory name says).
- `tests/unit/profile_parsing.bats` — `archwright_parse_profile_file`
  directly: unknown key, duplicate key, malformed line, all rejected;
  well-formed input round-trips correctly.
- `tests/unit/list_parsing.bats` — `archwright_read_list_file`: comments,
  blank lines, trailing whitespace, `#` mid-line.

Run a single file: `bats tests/unit/profile_parsing.bats`.

## Integration test — the idempotency claim

**Requires:** a way to run a systemd-capable Arch container. This is the
highest-risk piece of this project's CI to keep reliable long-term — see
`docs/decisions/0009-user-units-require-a-session-bus.md` for a related
containerization limitation, and the note at the bottom of this section.

`tests/integration/idempotency.sh` runs, in order, against
`examples/minimal-workspace`:

```
validate → plan → converge → converge (again) → drift
```

and fails (non-zero exit) unless:

1. `validate` exits `0`.
2. The first `plan` exits `2` (`EXIT_CHANGED` — a fresh container has
   neither `tree`/`openssh` installed nor `systemd-timesyncd.service`
   enabled). The example workspace deliberately declares a service whose
   unit file ships with `systemd` itself rather than with a package the
   same profile installs — see
   `docs/decisions/0013-roles-do-not-order-against-each-other.md` for why
   that pairing would make `plan` (which never applies anything) report
   `EXIT_VALIDATION_ERROR` instead.
3. The first `converge` exits `0` or `2`, and does not exit `4`/`5`
   (`EXIT_APPLY_FAILED`/`EXIT_VERIFY_FAILED`).
4. **The second `converge` exits exactly `0`** — this is the property the
   whole project exists to demonstrate. Any other exit code fails the
   test.
5. `drift` exits `0` or `2` — never `3`. It is **not** asserted to find zero
   divergence: a base container image legitimately has other explicitly-
   installed packages and enabled units beyond this workspace's two
   declarations, so `EXIT_CHANGED` (drift found something) is an expected,
   passing outcome here. What would fail the test is `EXIT_VALIDATION_ERROR`
   (an unresolved reference — a real bug) or a crash.

### Running it locally

```sh
docker run --rm -it \
  --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v "$PWD:/archwright:ro" \
  archlinux:base-devel \
  /archwright/tests/integration/idempotency.sh
```

(`base-devel` rather than the minimal `archlinux:base` image, because it
already includes the tools the test harness itself needs — `bash`,
`grep`, `awk` — without an extra install step inside the container.)

### Known fragility

Running systemd as PID 1 inside a container depends on the host's cgroup
setup (v1 vs. v2) and on `--privileged` being permitted by the CI runner —
this is a documented weak point of the whole approach, not a solved
problem. If `.github/workflows/integration.yml` starts flaking, the first
thing to check is whether the hosted runner's cgroup configuration changed
underneath it before assuming the test logic itself regressed. A
self-hosted runner with a known-good cgroup v2 setup is the most robust
long-term fix, tracked as an open risk rather than solved by this release.

## What is not tested yet

- The `services_user=` skip path (`docs/decisions/0009`) — the example
  workspace's user-services file is empty specifically to avoid depending
  on a session bus existing in CI, which means the skip behavior itself
  currently has no automated coverage.
- Concurrent/interrupted `converge` runs (what happens if the process is
  killed mid-`apply`) — out of scope for this release, noted as a risk in
  the top-level report, not silently ignored.
