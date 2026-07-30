# Getting started

This walks through the full command sequence against the bundled example
workspace. It doesn't touch your real system's package or service state
beyond what `examples/minimal-workspace` declares (`tree`, `openssh`,
`sshd.service` — see `examples/minimal-workspace/README.md` for why those
were chosen), and every command tells you what it's about to do before
`converge` does anything.

## Prerequisites

- Arch Linux (or an Arch container), bash ≥ 4.4, `pacman`, `systemd`.
- No secrets, no network access beyond pacman's own mirrors, no AUR helper.

## Run it

```sh
git clone https://github.com/nomadstar/archwright.git
cd archwright

# 1. Structure and every profile parse correctly?
./bin/archwright validate --workspace examples/minimal-workspace

# 2. What would converge do? (read-only)
./bin/archwright plan --workspace examples/minimal-workspace --profile ci

# 3. Actually converge (installs `tree`/`openssh` if missing, enables
#    sshd.service if disabled — requires root for those two operations)
sudo ./bin/archwright converge --workspace examples/minimal-workspace --profile ci

# 4. Run it again — this should report EXIT_OK (no changes) for every role
sudo ./bin/archwright converge --workspace examples/minimal-workspace --profile ci
echo "exit code: $?"   # expect 0

# 5. Report-only comparison of declared vs. real state
./bin/archwright drift --workspace examples/minimal-workspace --profile ci
```

Step 4 printing exit code `0` (not `2`) is the whole point of this
project's first release — see `docs/architecture.md`.

## Writing your own workspace

Not yet documented beyond the spec itself — start from
`docs/spec/workspace-layout.md` and use `examples/minimal-workspace` as a
skeleton to copy. A dedicated `writing-a-workspace.md` guide is planned
once the spec has had real use beyond the bundled example (see
`docs/decisions/0008-mvp-scope-cut.md`).
