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
| `asset-missing-payload-dir/` | `assets/manifest/` exists but `assets/payload/` does not |
| `asset-unknown-key/` | An asset manifest declares a key outside `docs/spec/assets-format.md`'s table (`owner=`) |
| `asset-duplicate-key/` | An asset manifest declares `dest_class=` twice |
| `asset-missing-required-key/` | An asset manifest omits the required `mode=` key |
| `asset-bad-dest-class/` | An asset manifest sets `dest_class=xdg_config` (only `home` is valid in spec v0.1) |
| `asset-path-traversal/` | An asset manifest's `dest_path=` contains `..` segments |
| `asset-bad-sha256/` | An asset manifest's `payload_sha256=` is not 64 lowercase hex characters |
| `asset-bad-size/` | An asset manifest's `size=` is not a base-10 integer |
| `asset-setuid-mode/` | An asset manifest's `mode=4755` sets the setuid bit |
| `asset-missing-payload/` | An asset manifest references a `payload_sha256` with no corresponding file under `assets/payload/` |
| `asset-corrupted-payload/` | A payload file's actual content does not hash to its own filename |
| `asset-duplicate-dest-path/` | Two asset manifests declare the same `dest_class`+`dest_path` |
| `asset-invalid-id/` | An asset manifest's filename (`InvalidID.conf`) does not match the id pattern (uppercase) |

See `docs/spec/` for what each of these rules means and why it's a hard
validation error rather than a warning.
