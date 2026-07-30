# Invalid workspace fixtures

Each directory here is broken in exactly **one** documented way, so
`tests/unit/workspace_validation.bats` can assert both "validation fails"
and "it fails for the right reason." If you add a new validation rule to
`lib/workspace.sh`, add a fixture here that exercises it before wiring the
rule into the bats test.

| Fixture | Breaks |
|---|---|
| `missing-version/` | No `.archwright-version` file |
| `missing-required-dirs/` | Has `.archwright-version` but none of `profiles/`, `packages/`, `services/` |
| `no-profiles/` | Has all required directories, but `profiles/` contains zero `*.conf` files |
| `duplicate-key-profile/` | `profiles/default.conf` declares `name=` twice |
| `dangling-reference/` | `profiles/default.conf` references a `packages/` file that does not exist |
| `unknown-key-profile/` | `profiles/default.conf` declares a key outside `docs/spec/profiles-format.md`'s table (`hostname=`) |
| `missing-required-key/` | `profiles/default.conf` omits the required `packages=` key |

See `docs/spec/` for what each of these rules means and why it's a hard
validation error rather than a warning.
