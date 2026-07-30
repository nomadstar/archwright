# minimal-workspace

A deliberately tiny, entirely fictional workspace that plays three roles at once:

1. **Documentation example** — referenced from `docs/getting-started.md` as the
   thing a first-time reader runs `archwright validate` against.
2. **Test fixture** — `tests/unit/` validates the parser and schema rules
   against this exact directory.
3. **CI integration fixture** — `tests/integration/idempotency.sh` runs the
   full `validate → plan → converge → converge → drift` sequence against it
   inside an ephemeral Arch container to prove convergence is idempotent.

It declares two packages (`tree`, `openssh`) and one system service
(`systemd-timesyncd.service`, shipped by `systemd` itself — deliberately
*not* by either declared package, see
`docs/decisions/0013-roles-do-not-order-against-each-other.md`) — chosen
because installing and enabling them has no side effects worth worrying
about in a throwaway container: no ports get opened by installation
alone, and `converge` only *enables* the unit, it never starts it.

**Do not use this as a template for your own workspace's secrets or
hardware profile** — it intentionally has neither. See
`docs/writing-a-workspace.md` for that.

```
archwright validate --workspace examples/minimal-workspace
archwright plan     --workspace examples/minimal-workspace --profile ci
archwright converge --workspace examples/minimal-workspace --profile ci
archwright drift    --workspace examples/minimal-workspace --profile ci
```
