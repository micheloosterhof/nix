# Build venues

Where each build runs, how the result reaches a machine, and the rule that
keeps GitHub optional. How the flake is organized is in
[architecture.md](architecture.md); the commands themselves are in
[operations.md](operations.md).

## The invariant

**Every machine can be updated from a local checkout with no GitHub
involvement.** GitHub may make an operation faster or more convenient; it may
never become the only way to perform it.

This is already true by construction and should stay that way:
`modules/nix-settings.nix` sets `fallback = true` and `connect-timeout = 5`,
so an unreachable or empty cache costs five seconds and the build proceeds
locally. Nothing in the fleet hard-depends on a remote artifact.

The practical test for any change proposed here: *unplug the network to
github.com and cachix. Can `make rebuild` still finish?* If not, the change
is wrong.

## Two hard constraints

Everything below follows from two facts about where Nix can build what:

- **A macOS runner cannot produce Linux paths.** Nix on macOS builds Linux
  derivations only through a Linux builder. GitHub's hosted macOS runners are
  themselves virtual machines and do not expose nested virtualization, so
  standing a builder VM up there is not practical. The observable symptom is
  neon's CI job failing on `system-path.drv` with
  `Required system: 'aarch64-linux'`.
- **A Linux runner cannot produce darwin paths.**

Which gives:

| output | system | can be built on |
|---|---|---|
| `nixosConfigurations.vm-aarch64-*` toplevel | aarch64-linux | Mac's linux-builder, `ubuntu-24.04-arm` |
| `nixosConfigurations.{wsl,helium,nitrogen}` toplevel | x86_64-linux | `ubuntu-latest`, helium over ssh |
| `darwinConfigurations.neon.system` | aarch64-darwin **+ aarch64-linux** | Mac, or `macos-latest` **plus** a Linux venue |
| `vmwareImage` | aarch64-linux | Mac's linux-builder, `ubuntu-24.04-arm` |
| `gce-image` (repart, no KVM) | either | any runner of that arch |
| `installer-iso`, `container-server` | either | any runner of that arch |
| WSL `installer` tarball | x86_64-linux | `ubuntu-latest`, helium over ssh |

Two consequences worth naming:

- **neon is the only output that spans both sides.** Its closure contains the
  customized linux-builder image, an aarch64-linux derivation. Any venue
  building neon needs that path handed to it from a Linux venue. This is
  structural, not an accident of configuration.
- **x86_64-linux is the awkward arch locally.** The Mac's linux-builder is
  aarch64, so wsl/helium/nitrogen closures and the x86_64 GCE image have no
  convenient local venue. CI is their natural home, with helium over ssh as
  the local escape hatch.

## Where GitHub earns its place

CI currently builds nine closures and throws all of them away. Every machine
then rebuilds the same paths from scratch. That is the single largest
avoidable cost in the current setup, and closing it is one change: **have CI
push what it builds, so `make rebuild` becomes a download instead of a
build.**

The beneficiaries, in order of how much they gain:

1. **nitrogen** — a small TransIP VPS currently compiling its own closure
   under `make remote/rebuild`.
2. **A fresh Mac** — see bootstrap below.
3. **Any new VM** — first `make rebuild` inside a freshly imaged dev VM.

The limit is storage. `docs/operations.md` records the cachix free tier at
5 GB, which whole host closures do not fit into. The rule that does fit:

> **Cache what cache.nixos.org lacks, not what it already has.**

For this fleet that delta is small and high-value:

- the customized linux-builder image (~3 GiB, the current sole occupant)
- the packages `modules/overlays.nix` cherry-picks from `nixpkgs-unstable`,
  which are exactly the paths that silently fall back to from-source builds
  after a bump (the zed-editor caveat in `operations.md`)

If that delta outgrows 5 GB, the options are a paid cachix tier or a
self-hosted store (attic, S3). Not a decision that needs making now, but the
trigger to watch for.

## Provisioning a new machine

| target | venue today | GitHub could | local fallback |
|---|---|---|---|
| fresh Mac (nix-darwin) | local | supply the builder image from cache | default builder variant, then switch |
| NixOS via nixos-anywhere | local (`make remote/provision`) | little — needs ssh to the target | unchanged |
| NixOS via nixos-infect | **no target exists** | — | — |
| VMware dev VM | local (`make vm/launch`) | build the VMDK | unchanged |
| GCE image | local (`make gce/image` + `gce/upload`) | build + upload via OIDC | unchanged |
| WSL tarball | awkward locally (x86_64) | natural CI artifact | helium over ssh |
| container / ISO | either | natural CI artifact | unchanged |

Notes on the three that are not straightforward:

**Fresh Mac.** The one genuine bootstrap dependency in the fleet: the
customized linux-builder image cannot be built without a working builder.
With CI keeping the image in the cache this resolves permanently and no
human step is involved. The no-GitHub path stays available and should stay
documented — activate once with nix-darwin's default builder variant, then
switch to the customized one.

**nixos-infect.** `operations.md` names it as the answer for hosts too small
for the nixos-anywhere kexec (~1 GB), but there is no `make` target and no
recipe. This is a real gap in the provisioning story, and it is a local-only
path by nature — GitHub cannot help reach a VPS rescue console.

**GCE upload.** Doing it from CI via OIDC to GCP workload identity
federation would need no long-lived key and would make image releases
repeatable. It also couples the repo to cloud credentials, so it is worth
doing only if image releases become routine rather than occasional.

## Updating an existing machine

- **Local host** — `make rebuild`. Must always work; this is the invariant.
- **Remote host** — `make remote/copy` then `make remote/rebuild`, which
  builds *on the target*. Two independent improvements, one per venue:
  - *GitHub:* the target substitutes from the cache instead of building.
  - *Local:* `nixos-rebuild --target-host` builds on the Mac or helium and
    copies the closure over, which needs no GitHub at all.

The symmetry is deliberate. Every acceleration listed here has a local
counterpart, which is what makes the invariant hold rather than merely being
asserted.

## The neon handoff

neon's closure spans both venues, so some venue must hand the Linux image to
the darwin build. There are exactly three ways to do that:

1. **The Mac seeds the cache by hand** (`make cachix/seed`). Works offline;
   needs a human after every lock bump that moves the image, and a red neon
   CI job as the reminder.
2. **CI seeds it from an arm Linux runner**, ahead of the closure matrix.
   Proven: the `linux-builder-image` job ran green on main.
3. **Drop neon from CI.** Removes the coupling entirely. `eval-tests` still
   forces neon's config on every push, so eval breakage is still caught, but
   the neon closure diff disappears from lock-bump PRs and darwin build
   failures surface only at `make switch`.

Applying the principle above gives 2 as the default and 1 as the retained
offline path — the handoff becomes automatic without becoming mandatory.
Option 3 remains the right answer only if the neon closure diff turns out
not to be worth a job.

## Known gaps

- **`update-lock` cannot pick up a CI fix.** The guard at
  `update-lock.yml:52-55` exits before the force-push when the lock is
  unchanged, so `flake-lock/weekly` is only ever rebuilt from main when the
  *inputs* move. A workflow fix landing on main never reaches an open bump
  PR; the branch has to be recreated by hand.
- **No nixos-infect path**, as above.
- **`CACHIX_TOKEN` is documented as unused** (`operations.md`, Binary cache),
  "reserved for selective CI pushing later". This design is that later.
- **The cache holds one artifact today.** Until CI pushes, every closure CI
  builds is discarded.
