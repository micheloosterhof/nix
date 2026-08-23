# Build venues

Where each build runs, how the result reaches a machine, and what keeps our
own CI and cache optional. How the flake is organized is in
[architecture.md](architecture.md); the commands themselves are in
[operations.md](operations.md).

## What must stay true

**No machine may depend on *our* CI or *our* cache.** They may make an
operation faster; they may never become the only way to perform it.

"GitHub" is three separate dependencies, and only two of them are ours to
control:

| role | ours? | optional? |
|---|---|---|
| github.com as flake-input source (`flake.lock` pins `github:` URLs) | no — shared with every Nix user | no |
| GitHub Actions as a build venue | yes | **yes** |
| cachix as an artifact store | yes | **yes** |

So the test is not "unplug github.com" — a fresh checkout or any lock bump
must fetch inputs from there, and always will. The test is:

> Disable the cachix substituter and never run a workflow. Can every machine
> still be built and updated?

That passes today by construction: `modules/nix-settings.nix` sets
`fallback = true` and `connect-timeout = 5`, so an unreachable or empty cache
costs five seconds and the build proceeds locally. Any change proposed here
has to keep it passing.

## Two hard constraints

- **A macOS runner cannot produce Linux paths.** Nix on macOS builds Linux
  derivations only through a Linux builder, and no runner here configures
  one. (The observed failure — `system-path.drv`,
  `Required system: 'aarch64-linux'` — proves only that. Whether a builder
  VM *could* run on a hosted macOS runner is untested; hosted runners are
  themselves VMs, so QEMU would likely fall back to unaccelerated TCG.
  Nobody has measured it, and the design does not depend on the answer.)
- **A Linux runner cannot produce darwin paths.**

| output | system | can be built on |
|---|---|---|
| `nixosConfigurations.vm-aarch64-*` toplevel | aarch64-linux | Mac's linux-builder, `ubuntu-24.04-arm` |
| `nixosConfigurations.{wsl,helium,nitrogen}` toplevel | x86_64-linux | `ubuntu-latest`, an x86_64 Linux box over ssh |
| `darwinConfigurations.neon.system` | aarch64-darwin **+ aarch64-linux** | Mac, or `macos-latest` **plus** a Linux venue |
| `vmwareImage` | aarch64-linux | Mac's linux-builder, `ubuntu-24.04-arm` |
| `gce-image` (repart, no KVM) | either | any runner of that arch |
| `installer-iso`, `container-server` | either | any runner of that arch |
| WSL `installer` tarball | x86_64-linux | `ubuntu-latest`, an x86_64 Linux box over ssh |

Two consequences:

- **neon is the only output that spans both sides**, because its closure
  contains the customized linux-builder image. Any venue *building* neon
  needs that aarch64-linux path handed to it. This is structural.
- **x86_64-linux is the awkward arch locally.** The Mac's linux-builder is
  aarch64, so the wsl/helium/nitrogen closures and the x86_64 GCE image have
  no convenient local venue. CI is their natural home, with an x86_64 Linux
  box over ssh as the local escape hatch.

## Evaluation and building are separate questions

The constraints above bind *building*. Evaluation is unconstrained: a Linux
runner evaluates the darwin config fine, and reaches the identical
derivation. Verified on an x86_64 Linux host against this flake:

```
nix eval --raw '.#darwinConfigurations.neon.config.system.build.toplevel.drvPath'
/nix/store/299jbrpq2iiw7lhr04mqg6yx65m0bkp4-darwin-system-26.05.c3e90c8.drv
```

Byte-identical to the same command on the Mac. Forcing a `drvPath` evaluates
the whole configuration and builds nothing, so **full eval coverage of every
host is available on any runner, for free.**

This matters because it is what a build job adds *on top of* eval that has
to justify the venue gymnastics. `nix flake check` does not evaluate
`darwinConfigurations` (not a standard flake output), and the eval tests
historically forced only specific slices of neon — so eval breakage in the
mac config could reach `make rebuild` undetected. The
`testDarwinToplevelEvaluates` eval test closes that gap by forcing
`mac.system.build.toplevel.drvPath` on the Linux runner `check.yml` already
uses.

## The neon handoff

Some venue must hand the Linux image to a darwin build — but only if a
darwin *build* happens in CI at all. Three options:

1. **The Mac seeds the cache by hand** (`make cachix/seed`). Works offline;
   needs a human after every lock bump that moves the image, with a red neon
   CI job as the reminder.
2. **CI seeds it from an arm Linux runner** ahead of the closure matrix.
   Proven to work, but see the costs below.
3. **Drop neon from the build matrix** and add the `toplevel.drvPath` eval
   test. Full eval coverage of neon on every push — strictly more eval than
   the old slice tests gave. What is lost is proof that darwin *packages
   compile*, and the neon entry in the lock-bump closure-diff comment.

**Option 3 is the decision.** It removes the macOS runner, the seeding
job, the cross-venue handoff, the `CACHIX_TOKEN` exposure in CI, and the
failure modes option 2 showed — while *increasing* eval coverage.
The residual risk is a darwin package that evaluates but fails to build,
which surfaces at `make rebuild` with a generation to roll back to.

Two things reduce that residual risk further. `modules/diff.nix` already
prints `nix store diff-closures` at every activation, so the neon closure
diff is not lost, only moved to the moment you rebuild — and neon is the
host rebuilt by hand most often. And `make cachix/seed` stays as the
fresh-Mac bootstrap path, which is a local operation with no CI involvement.

Two consequences to accept with open eyes:

- **The staleness signal goes away.** Today a red neon job announces that a
  lock bump moved the builder image. Without it, nothing does — benignly: a
  stale cached image has a different store path and is simply never matched,
  so a fresh Mac misses the cache and takes the default-builder route. The
  shortcut stops helping; nothing breaks.
- **neon becomes the least-covered host in CI overall.** It is already
  absent from `dependency-graph.yml` (which matrices over
  `nixosConfigurations` only), so GitHub advisories do not cover it. With
  the build job gone its CI story is eval-only — still strictly more eval
  than today, but the aggregate position should be stated, not just the
  delta.

Housekeeping if option 3 lands: drop the cachix `extra_nix_config` from
`build.yml` (no remaining job reads that cache; hosts keep their
substituter — that is the fresh-Mac path), and update the stale
descriptions of the manual-seed flow in `AGENTS.md` and
`operations.md`.

Option 2 was implemented and ran green, then rejected: it only seeded the
triggering ref's image (the bump-branch diff needs *main's* image too), its
`needs:` barrier let a cachix or arm-runner incident block all nine
closures, and it put a fleet-trusted write token into CI. Recorded so it is
not re-proposed; if a darwin build job is ever wanted again, move the image
between jobs as a run artifact (`nix copy --to file://`), not through the
cache.

**The closure diff stays.** Every defect above was neon's, not the diff's:
with neon out of the matrix, `--fallback` genuinely covers every remaining
job, main's closure builds on the runner without any cache, and the diff
runs only on `flake-lock/*` branches — weekly runner minutes, zero
structural coupling. The bump PR keeps its per-host what-changes view.

## Caching what CI builds

CI builds nine closures on every push and discards all of them; every
machine then rebuilds the same paths. Closing that would turn
`make remote/rebuild` on nitrogen from a compile into a download, and is
independent of the neon question.

The obstacle is storage: `operations.md` records the cachix free tier at
5 GB, which whole host closures do not fit into. The intent is to cache only
what cache.nixos.org lacks — but that is a goal, not yet a mechanism:

- `cachix push` skips paths already in *that cachix cache*. It knows nothing
  about what cache.nixos.org holds, so pushing a closure uploads plenty that
  upstream already serves. A real implementation has to filter explicitly
  (`nix path-info --store https://cache.nixos.org` per path, push the
  misses).
- The delta is not static. Right after a nixpkgs bump upstream lags, so the
  set of missing paths is temporarily far larger than the steady-state
  answer of "the linux-builder image plus the `nixpkgs-unstable` packages
  `modules/overlays.nix` cherry-picks".

Until that filter exists, this stays a proposal rather than a policy.

**The cache is a fleet-wide trust root.** Every host trusts its signing key
as a substituter (`modules/nix-settings.nix`), so write access means
arbitrary store paths that every machine will accept. Fork PRs on a public
repo get no secrets, but any commit on any branch of this repo does. If CI
starts pushing, the push must be restricted to trusted refs (`main` and
`flake-lock/*`), and the token treated as fleet-level credential rather than
CI plumbing.

## Provisioning a new machine

| target | venue today | GitHub could | local fallback |
|---|---|---|---|
| fresh Mac (nix-darwin) | local | supply the builder image from cache | default builder variant, then switch |
| NixOS via nixos-anywhere | local (`make remote/provision`) | little — needs ssh to the target | unchanged |
| NixOS via nixos-infect | **no target exists** | — | — |
| VMware dev VM | local (`make vm/launch`) | build the VMDK | unchanged |
| GCE image | local (`make gce/image` + `gce/upload`) | build + upload via OIDC | unchanged |
| WSL tarball | awkward locally (x86_64) | natural CI artifact | x86_64 box over ssh |
| container / ISO | either | natural CI artifact | unchanged |

**Fresh Mac.** The one genuine bootstrap dependency: the customized
linux-builder image cannot be built without a working builder. The local
path is to activate once with nix-darwin's default builder variant and then
switch to the customized one; `make cachix/seed` from an existing Mac makes
the shortcut available. Keep both documented.

**nixos-infect.** `operations.md` names it as the answer for hosts too small
for the nixos-anywhere kexec (~1 GB), but there is no target and no recipe.
A real gap, and local-only by nature — CI cannot reach a VPS rescue console.

**GCE upload.** Running it from CI via OIDC to GCP workload identity
federation needs no long-lived key and makes image releases repeatable. It
also couples the repo to cloud credentials, so it is worth doing only if
image releases become routine.

## Updating an existing machine

- **Local host** — `make rebuild`. Must always work; this is the invariant.
- **Remote host** — `make remote/copy` then `make remote/rebuild`, which
  builds *on the target*. One improvement per venue:
  - *CI:* the target substitutes from the cache instead of building.
  - *Local:* `nixos-rebuild --target-host` builds elsewhere and copies the
    closure over, needing no CI at all — but only from a machine of the
    right arch. For nitrogen (x86_64) the Mac cannot be that machine; the
    local alternative is another x86_64 box, or nitrogen building on
    itself as it does today.

The invariant holds because building on the target always works. The
accelerations are conveniences on top, and for x86_64 hosts the local
convenience needs x86_64 hardware — CI is genuinely the only *always-on*
x86_64 venue in this fleet.

## Open questions

- **Three near-identical arm VM builds.** fusion/utm/apple differ by
  platform glue over one workstation config; three full closure builds per
  push buy little beyond the first. A representative build (fusion, the one
  with an image output) plus the `toplevel.drvPath` eval test for the other
  two would cut the matrix by two jobs. Cost: a utm- or apple-only build
  breakage surfaces at rebuild time instead of CI.
- **Should `operations.md` describe the venue split at all?** This area now
  spans three documents that must change together (`AGENTS.md`,
  `operations.md`, this file). Likely answer: `operations.md` keeps the
  commands, this file keeps the reasoning, and each points at the other.

## Known gaps

- **`update-lock` cannot pick up a CI fix.** The guard at
  `update-lock.yml:52-55` exits before the force-push when the lock is
  unchanged, so `flake-lock/weekly` is rebuilt from main only when the
  *inputs* move. A workflow fix landing on main never reaches an open bump
  PR; the branch has to be recreated by hand.
- **No nixos-infect path.**
- **`build.yml` claims `--fallback` covers a missing path.** True for every
  job except neon, where a missing aarch64-linux path cannot be built on the
  runner at all.
- ~~The eval tests do not force any host's `toplevel`.~~ Resolved: `nix
  flake check` already evaluates every nixosConfiguration's toplevel (only
  `darwinConfigurations` is skipped, as a nonstandard output), and the
  eval tests now force neon's (`testDarwinToplevelEvaluates`).
