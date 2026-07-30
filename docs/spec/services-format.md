# `services/*.txt` format — v0

Same grammar as `packages/*.txt` (see `packages-format.md`): one systemd
unit name per line, `#` comments, blank lines ignored.

```
# services/system.txt
systemd-timesyncd.service
```

## System vs. user units — separate files, not a prefix

A profile references system units and user units through two distinct keys
(`services_system=`, `services_user=`), each pointing at its own file(s).
There is no in-file marker for scope — mixing system and user unit names in
the same file and expecting the engine to sort them out is not supported;
put them in separate files instead.

## Validation

| Condition | Bucket |
|---|---|
| Declared unit name has no corresponding unit file at all (`systemctl list-unit-files` finds nothing) | **Blocks that role's convergence** — reported as `status=unresolvable`, `EXIT_VALIDATION_ERROR` for that role's check. **Caveat:** if the unit file is shipped by a package this same profile declares but hasn't installed yet, `check()`/`plan` will report this even though `converge` would succeed (package role's `apply()` runs first) — see `docs/decisions/0013-roles-do-not-order-against-each-other.md`. Avoid the false positive by not pairing a package with the service it provides in the same profile. |
| Declared unit exists but is already enabled | **No-op**, reported as `status=ok`. |
| Declared unit exists and is disabled | Reported as `status=missing`; `converge` enables it. |
| A `services_user=` file is declared but no systemd user session bus is reachable (e.g. a minimal CI container) | **Skipped, not an error** — reported as `status=skipped`. This is a known limitation of v0, not a silent success: see `docs/decisions/0009-user-units-require-a-session-bus.md`. |
| A unit is enabled on the system but not declared in any file the active profile references | **Informational** — reported as `status=undeclared`. Never disabled automatically. |

`converge` only ever runs `systemctl enable` (or `systemctl --user enable`).
It never runs `--now`, and it never disables anything — see
`docs/decisions/0005-no-automatic-removal.md`.
