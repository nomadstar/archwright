# Getting started

This walks through the full command sequence against the bundled example
workspace. It doesn't touch your real system's package or service state
beyond what `examples/minimal-workspace` declares (`tree`, `openssh`,
`systemd-timesyncd.service` — see `examples/minimal-workspace/README.md`
for why those were chosen), and every command tells you what it's about
to do before `converge` does anything. It does write one small file under
your own `$HOME` (`~/.local/share/archwright-example/note.txt`, from the
workspace's one declared asset — see "Declared assets" below).

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
#    systemd-timesyncd.service if disabled — requires root for those two
#    operations)
sudo ./bin/archwright converge --workspace examples/minimal-workspace --profile ci

# 4. Run it again — this should report EXIT_OK (no changes) for every role
sudo ./bin/archwright converge --workspace examples/minimal-workspace --profile ci
echo "exit code: $?"   # expect 0

# 5. Report-only comparison of declared vs. real state
./bin/archwright drift --workspace examples/minimal-workspace --profile ci
```

Step 4 printing exit code `0` (not `2`) is the whole point of this
project's first release — see `docs/architecture.md`.

## Declared assets

`converge` also restores any declared assets (`assets/manifest/*.conf`)
to their destination under `$HOME` — the bundled example declares one
(`examples/minimal-workspace/assets/manifest/example-note.conf`), so step
3 above also creates `~/.local/share/archwright-example/note.txt`. See
`docs/spec/assets-format.md` and
`docs/decisions/0014-declared-assets-and-capture-restore-lifecycle.md` for
the full design.

To declare your own:

```sh
# 1. See what a config file already on disk references (read-only, never
#    scans anything you don't name explicitly)
./bin/archwright asset scan ~/.config/i3/config --workspace <your-workspace>

# 2. Explicitly capture one file into the workspace (system -> workspace)
./bin/archwright asset capture ~/Pictures/wallpapers/forest.jpg --workspace <your-workspace>

# 3. See everything currently declared
./bin/archwright asset list --workspace <your-workspace>

# 4. `archwright converge` (see above) restores every declared asset —
#    workspace -> system, the opposite direction from capture.
```

## Writing your own workspace

Not yet documented beyond the spec itself — start from
`docs/spec/workspace-layout.md` and use `examples/minimal-workspace` as a
skeleton to copy. A dedicated `writing-a-workspace.md` guide is planned
once the spec has had real use beyond the bundled example (see
`docs/decisions/0008-mvp-scope-cut.md`).
