# Research: Distributed Reconstruction

**Status: exploratory. Not an ADR, not an RFC, not a design.** This
document exists to determine whether "distributed reconstruction"
deserves to become a future architectural direction for Archwright — not
to specify how it would work if pursued. No command names, APIs, file
formats, or filesystem layouts appear below on purpose.

---

## 1. The fundamental question, challenged

> *A machine should not survive because its disk survives. A machine
> should survive because its description survives.*

Taken literally, this statement is **false**. It is a good design north
star for one layer of a machine, and a category error if applied to the
whole machine.

### Where it holds

For the layer Archwright already proves — packages, services, and now
individually declared assets — the statement is close to demonstrably
true, and CI already enforces the weaker, checkable version of it
(idempotent convergence). This is genuinely the load-bearing insight
behind the whole project, and this exploration doesn't undermine it.

### Where it breaks

- **Data has no formula.** A package name or a systemd unit is low-entropy
  — a short string reconstructs a large, well-defined artifact because an
  external authority (a package repo) already did the expensive work of
  producing that artifact from the description. A photo, a database, a
  private key, a chat history has no such generating function. No
  description, however complete, reconstructs content that was never
  derived from anything — it can only *point at* a copy that must already
  exist somewhere. The statement silently substitutes "the software
  environment" for "the machine," and those are not the same thing. A
  machine is software *plus* the state a person actually cared about
  keeping; the statement is true of the first term and false of the sum.

- **Machine-unique state resists "reconstruction" as a concept.** A host
  SSH key, `systemd`'s machine-id, a TPM-sealed disk encryption key: these
  aren't things a description should reproduce identically — reproducing
  a host key exactly would usually be a *security bug*, not a feature.
  "Reconstruction" quietly assumes everything about the old machine is
  worth restoring; some of it should be deliberately regenerated instead,
  and a design in this space has to say which is which, item by item, not
  wave at the distinction.

- **The description depends on continuity it doesn't control.** A
  `packages/*.txt` entry names a package, not a pinned, hashed build of
  one. If the upstream repo or mirror that resolves that name stops
  existing, or silently starts resolving it to different bits five years
  from now, "the description survives" but the *thing it described* may
  not, or may not be the same thing anymore. Describability is necessary
  for reproducibility but not sufficient — it also requires the
  *reproducer* (the repo, the mirror, the registry) to remain reachable
  and to remain honest about what a name means over time. NixOS and Guix
  take this seriously by pinning exact derivations rather than trusting a
  mutable name; Archwright's `package` role deliberately doesn't (see
  §7) — that's a real, current gap in how far "survives via description"
  can honestly be claimed today, independent of anything proposed here.

**Reframed, defensibly:** *the reproducible portion of a machine can
survive by description; the irreproducible portion can only survive by
preservation; a machine, as a whole, survives only when both are
available and correctly combined.* The rest of this document uses that
reframing, not the original claim.

---

## 2. Reproducibility, Backup, and Recovery

These are usefully distinct, and Archwright currently only has a real
answer for the first one.

**Reproducibility** — what Archwright already does. Deterministic-ish
(see the pinning caveat above), cheap to store, safe to make public (it
describes structure, not content — with one deliberate, narrow exception:
see below), and its correctness is *provable*, which is precisely why the
idempotency claim is the thing CI checks on every push.

**Backup** — preserving content that has no generating function.
Fundamentally different requirements: much larger volume, needs
versioning and incremental storage, doesn't benefit from "convergence"
(there is no declared target state for a photo, only a most-recent
snapshot to restore), and frequently needs encryption at rest because the
content itself, not just its structure, is sensitive.

**Recovery** — the event where both are needed together, in the right
order. A database restored before the service that owns it exists (with
its schema, its permissions, its listening state) is not a recovered
system, it's a data file sitting next to a service that doesn't know what
to do with it. Sequencing is not a footnote here; it's most of the actual
difficulty.

A quiet observation worth stating plainly: **`assets` (already shipped)
already crossed the Reproducibility/Backup line, on purpose, in a very
narrow way.** A captured wallpaper or script is literal bytes, not a
generating formula — it's small-scale backup wearing reproducibility's
clothes, made safe only by deliberate constraints (single files, a size
ceiling, a hard denylist). That precedent is useful evidence for how this
project tends to cross this exact boundary responsibly when it has to:
narrowly, explicitly, with hard limits, never as a general mechanism.

### Should Recovery become first-class?

**Argument for:** Recovery has its own state machine (what's been
reproduced, what's been restored, in what order, what's still missing)
that doesn't fit cleanly inside "convergence." Naming it explicitly would
let Archwright report a recovery status distinct from a convergence
status, and would give workspace authors a place to declare "this data
lives in that backup tool" instead of pretending everything is an asset.

**Argument against:** this is exactly the shape of scope growth the
manifesto warns about — "we are not trying to build the most powerful
configuration framework," "every new feature must justify the complexity
it introduces." Backup is a mature, hard problem with excellent existing
tools (§7). Recovery becoming first-class risks Archwright starting to
look like it thinks it *is* a backup tool.

**A middle path worth naming:** Recovery could become first-class as a
**boundary**, not an implementation — Archwright declares *which* external
tool owns which data and exposes that as part of a workspace's declared
state, the same way the secrets-provider-interface page already reserves
a slot for "something else manages this, we don't reimplement it," rather
than Archwright ever touching the data itself. That's consistent with the
project's existing preference for wrapping native tools (ADR 0001) over
reimplementing them.

---

## 3. Distributed reconstruction, examined

The premise — no single store contains a complete system, so maybe the
system can emerge from coordinating several — is worth separating from
what's actually new here. **Distribution itself is not new.** Archwright
already depends on a distributed resource for reproducibility: pacman
mirrors. What's actually being proposed is *formalizing* the coordination
that already exists implicitly (you already trust official repos exist;
you already, separately, trust you remember where your backups live) into
something explicit and declared.

Reframed that way, the useful version of this idea is closer to: **a
declared dependency/provenance graph for what a full reconstruction
requires** — this workspace's own remote, the pacman mirrors it
implicitly relies on, an object store if the asset payload store outgrows
what's comfortable in git, a secret manager for anything sensitive, a
named backup tool for user data — plus a way to check that each is
currently reachable. That is closer to Terraform's relationship to a
cloud provider's state than to a new storage system: Terraform doesn't
store your infrastructure, it describes and verifies it. That's the
version of this idea most compatible with "Archwright is the engine, not
another operating system."

### Where the idea breaks

Coordinating N independently-operated stores inherits a consistency
problem a single source of truth never has: the workspace description can
say "asset X hashes to H, held in store B," while B's content silently
diverges, and the workspace itself has **no way to know it went wrong
until someone actually attempts reconstruction** — potentially years
later, on the one occasion it matters most. This is a sharper, larger
version of the "missing payload / corrupted payload" problem ADR 0014
already had to solve for one local store, now spread across N stores with
N different availability and consistency models Archwright doesn't
control.

The entire value of "this workspace is provably self-sufficient" would
depend on *periodically, actively verifying reachability* across every
declared provider — which is a background job with its own reliability
requirements. That is, ironically, close to the "hidden state / daemon"
shape the project has deliberately avoided everywhere else ("there is no
state file, no database, no daemon... every invocation queries the real
system fresh"). A static description that's only checked at
reconstruction time is honest about being unverified; a description that
claims to be continuously verified requires exactly the kind of
persistent, running component this project has architecturally opted out
of so far.

---

## 4. Security

- **Loss of hardware** — this is the case the reproducible layer is built
  for and handles well. It is *not* handled for the backup layer unless
  backup already existed independently beforehand; nothing about
  reproducibility protects data it was never designed to hold.

- **Theft** — two different problems. Theft of the machine exposes
  whatever was cached locally (an unencrypted local asset/payload store
  becomes readable by whoever now has the laptop). Theft of *credentials*
  that grant reconstruction access is a different, arguably worse
  problem: if reconstruction requires assembling several providers, an
  attacker needs only the **weakest** credential among them, not the
  strongest. Distribution doesn't average risk across providers, it sums
  the attack surface.

- **Provider compromise** — whatever a compromised provider stores is the
  attacker's, unless it was encrypted client-side before it ever left the
  machine. This makes the still-unimplemented secrets-provider interface
  a *prerequisite*, not an optional nicety, for taking this direction
  seriously for anything sensitive.

- **Provider disappearance** — the mundane, highest-likelihood failure
  mode of all of these: services shut down, free tiers get revoked,
  accounts get closed, hosts change policy. A description that names N
  providers is only as durable as the **least** durable one it depends
  on, unless the workspace can declare (and something can verify)
  redundancy rather than mere location.

- **Partial corruption** — the same class of bug ADR 0014 already solved
  once (hash mismatch = corrupted, caught at validate/converge time),
  multiplied across stores, plus a harder new problem: partial corruption
  of *one* provider mid-reconstruction can leave a machine in a state
  that's genuinely ambiguous to reason about — packages converged,
  assets converged, but a data restore stopped halfway. What is "the
  state" of that machine, and who decides?

- **Integrity verification** — content-addressing, already used for
  assets, is exactly the right primitive to keep leaning on: hashes are
  cheap to carry and verifiable independent of trusting any one provider.

- **Client-side encryption** — necessary before anything sensitive is
  allowed near a third-party store. Pursuing this direction without first
  landing real secrets handling means shipping a system whose headline
  promise (reconstruct anything from anywhere) is unsafe to use for
  almost everything worth reconstructing.

- **Secret separation** — today, the workspace is assumed non-secret and
  safe to publish (ADR 0015 exists specifically to make that publishable
  safely). A workspace that must now *reference* where secrets live —
  which provider, which key — turns that reference list itself into
  sensitive metadata: even containing no secret directly, it tells an
  attacker exactly where to go next.

- **Trust boundaries** — today's threat model is narrow and well-defined:
  a workspace might be a compromised repo, but is otherwise fully trusted
  local description (ADR 0007); ADR 0015 adds exactly one new,
  deliberately scoped external trust boundary (a chosen git provider).
  Distributed reconstruction adds N independently-operated boundaries at
  once. Coordinating trust across N third parties is not a bigger version
  of the same problem ADR 0015 solved — it's a different, harder one, and
  probably the sharpest tension with "simplicity is a feature" in this
  entire document.

---

## 5. Philosophy

**Aligned:** "Infrastructure is knowledge, knowledge deserves permanence"
— this document's premise reads as the logical extension of the
manifesto's own opening argument, not a departure from it. "Open by
design" (framework public, workspace personal) survives intact as long as
a reconstruction graph stays a *description of where things live*, never
a place where things live.

**In tension:** "Simplicity is a feature... every abstraction has a
cost... if a feature makes the framework harder to understand than the
problem it solves, it probably does not belong." Coordinating several
storage providers, encryption, and secret separation is a large increase
in surface area for a project whose proof-of-concept to date is
deliberately narrow (two roles, now three, one MVP property proven by
CI). The ambition here is a faithful descendant of the manifesto; the
likely execution cuts hard against "small components, clear
responsibilities, predictable execution."

**In tension:** "The system is the state... truth should never exist in
two places." Distributed reconstruction, by construction, spreads truth
across several external systems Archwright doesn't control and can't
force to agree. `assets` already accepted a milder version of this
tension (payload lives in git, "real" state lives on the target
filesystem); this proposal scales that same tension to several
independent third parties at once, where disagreement is far harder to
detect.

**Would need new, explicit principles**, stated with the same sharpness
as existing ADRs (0001, 0007, 0010): something like *"Archwright
coordinates external systems of record; it does not become one,"* and
something like *"reconstruction is verified-as-of-last-check, not
guaranteed — this is a different, weaker kind of promise than the
idempotency proof, and must never be presented as equivalent to it."*

---

## 6. Failure modes, and how they'd need to be communicated

- **Packages removed upstream** — the description survives, the target
  doesn't. This already has a home in the existing vocabulary: it's the
  same shape as `unresolvable`, just triggered by time instead of an
  AUR-only name. Reuse the pattern (explicit per-item status, never
  silent) rather than inventing a new one.

- **Storage unavailable** — transient and permanent are very different
  and today's exit-code vocabulary has no room for "can't reach it right
  now, try again" versus "confirmed gone." That distinction would need a
  real answer, not a shrug.

- **Hardware-specific drivers** — outside the describable layer entirely,
  already and explicitly out of scope (ADR 0008). More providers do not
  touch this problem at all; worth stating plainly so this exploration
  isn't read as quietly reopening it.

- **Architecture changes** — a description assumes architecture
  continuity that was never actually promised. A package name may simply
  not resolve on a new architecture. "The description survives" quietly
  assumed "on the same kind of machine," which is usually but not always
  true.

- **Revoked credentials** — reachable and authorized are different
  things; an account ban or an unrotated token can make a perfectly
  healthy provider unusable. This looks identical to "storage
  unavailable" from the outside but has a completely different fix
  (re-authenticate vs. find a new provider) and should be surfaced as a
  distinct state, not folded into a generic failure.

- **Expired encryption keys** — the sharpest failure mode in this whole
  document. Unlike a revoked credential, a lost or expired decryption key
  can make preserved data **permanently** unrecoverable even though the
  storage holding it is perfectly fine. This is the one case where "the
  description survives" is entirely beside the point, because what the
  description points at is cryptographically gone. Any real design here
  needs a first-class answer for how keys themselves stay reconstructible
  — which is a bootstrapping problem, since the mechanism that recovers a
  key can't itself depend on the key it's meant to recover.

---

## 7. Comparison

- **Disk images** — preserve everything, including the irreproducible
  parts, at the cost of being enormous, hardware-coupled, and opaque (you
  cannot diff or review a disk image the way you can a text description).
  The exact opposite tradeoff from Archwright's premise.

- **rsync / Borg / Restic** — excellent, mature answers to exactly what
  this document calls "Backup." Strong candidates for *the* tool a
  workspace names as its data owner, rather than anything worth
  reimplementing.

- **NixOS / Guix** — the closest philosophical relative on the
  Reproducibility side, and worth naming honestly rather than glossing
  over: they pin exact, content-addressed derivations, which is a
  **stronger** reproducibility guarantee than Archwright currently
  offers. `package` trusts pacman to resolve a name to whatever it
  currently resolves to (ADR 0001's deliberate choice); Nix/Guix don't
  extend that trust. Taking "description survives" seriously over long
  time horizons is a solved problem elsewhere — Archwright just hasn't
  adopted that solution, on purpose, for simplicity.

- **Ansible / Terraform** — same declare-and-converge lineage. Terraform
  in particular already routinely spans multiple providers in one state
  (cloud + DNS + git, etc.), making it the closest existing precedent for
  "coordinate several external systems from one declared source." Its
  handling of partial-apply/partial-failure across providers is directly
  relevant prior art for the consistency problem raised in §3, and worth
  studying specifically rather than reinvented from scratch if this
  direction is ever pursued.

- **cloud-init** — closest in spirit to "bootstrap a fresh machine from a
  declaration," but only at first boot, with no ongoing convergence and
  no idempotency proof. Useful mainly as a reminder of a problem this
  document hasn't addressed: the chicken-and-egg of needing network and
  credentials before a bare machine can even fetch the description that
  tells it what it needs.

---

## 8. Open questions

Deliberately unanswered — each is plausibly its own future ADR or RFC.

1. What is the minimum bootstrap requirement (network, credentials, a
   binary) to go from bare hardware to "can start reading the workspace
   description" at all — and how does *that* stay reconstructible, given
   it can't depend on the thing it bootstraps?
2. Should a workspace be able to declare a minimum replication factor for
   a dependency ("retrievable from at least 2 of 3 declared sources"),
   and if so, whose job is verifying that?
3. What vocabulary describes provider-level trust/reachability states,
   distinct from today's local-system status vocabulary
   (`ok`/`missing`/`unresolvable`/...)?
4. Does Recovery get its own explicit concept, or stay purely a handoff
   to an external, named tool?
5. How does key-recovery for encrypted preserved data get bootstrapped
   without depending circularly on itself?
6. Is "reconstructing this exact machine" meaningfully different from
   "reconstructing a machine of this class" — does identity (hostnames,
   host keys) get restored or deliberately regenerated, and does the
   answer differ per item?
7. When declared providers disagree about the same artifact, who is
   authoritative, and how is that declared rather than assumed?
8. Should reachability of declared providers be actively, periodically
   checked, and if so, does that reintroduce the persistent-process
   pattern this project has avoided everywhere else?
9. At what point does "coordinating providers" become indistinguishable
   from "being a distributed storage system," and is crossing that line
   ever acceptable under the simplicity principle?
10. Is version/hash-pinning (Nix/Guix-style) a prerequisite for taking
    "description survives" seriously over long time horizons, and if so,
    is that compatible with ADR 0001's choice to trust pacman as-is?

---

## 9. Verdict

**Not fundamentally flawed — but the two halves of the idea deserve very
different confidence levels, and should not be adopted as a package.**

The **Reproducibility** half is not really a new direction at all; it's
close to already proven, and this document mostly confirms that the
existing design (`package`/`service`/`assets`, content-addressed,
explicitly declared, never inferred) is the right shape to keep extending.

The **distributed, multi-provider, backup-coordinating** half is where
the real tension lives. It is conceptually sound — the Terraform
comparison shows the pattern works elsewhere — but represents a large,
qualitative jump in trust surface, operational complexity, and security
responsibility that the project's own stated principles would resist if
adopted wholesale. Pursued narrowly, it is plausible: (a) treat Recovery
as a declared **boundary** to named external tools rather than something
Archwright implements, and (b) treat "distributed" as *declaring and
verifying reachability of a small, explicit list of dependencies* rather
than *actively orchestrating synchronized state across them*. Pursued as
a general-purpose multi-provider storage/reconstruction platform, it
would very likely violate the manifesto's own simplicity principle before
it violated anything else.

The opening statement this document was asked to challenge does not
survive scrutiny as written — but a corrected version of it
("reproducible state survives by description, irreproducible state
survives by preservation, a machine survives by their coordination") is
both true and already the direction the project has been moving in since
`assets` first blurred the reproducibility/backup line on purpose. That
correction, not the original claim, is what's worth carrying forward.
