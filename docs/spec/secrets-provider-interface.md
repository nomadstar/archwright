# Secrets provider interface — not yet implemented

**This document exists to settle the shape of the interface before any code
is written against it. There is no `providers/` directory and no secrets
handling anywhere in the engine yet.** Roles in this release (`package`,
`service`) never touch secrets. See `docs/decisions/0008-mvp-scope-cut.md`
for why this was cut from the first release, and the "Riesgos" /
"Gobernanza" sections of the architecture doc referenced there for the
fuller design (sops+age as the reference implementation, secrets scoped by
directory, identities recovered on demand rather than resident on disk).

When implemented, a provider is expected to expose three operations to the
engine, none of which the engine implements itself:

```text
provider_unlock()            # make decryption possible for this run
provider_decrypt(<file>)     # -> plaintext on stdout, for exactly one file
provider_lock()               # tear down whatever unlock() set up
```

The engine's obligations, once this exists, will be:

- never write a value returned by `provider_decrypt` to a persistent path;
- always call `provider_lock` on exit, including on error paths;
- never log a decrypted value, only the fact that a decrypt happened.

This page is intentionally short. Expanding it into a real interface
(argument passing, error signaling, how a workspace declares which
provider it uses) is future work, tracked as a candidate RFC once a role
that needs secrets is proposed.
