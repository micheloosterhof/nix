# Operations

Build, deploy, and maintenance. Everything goes through the `Makefile`; run
`make` (no args) for the target menu. How the flake itself is organized is in
[architecture.md](architecture.md).

## Local rebuild

`make rebuild` builds and activates the local host; `make test` activates
without persisting a boot entry; `make build` only builds; `make check` runs
the activation checks without switching.

The local config name (`LOCAL_NAME`) is picked automatically:
`neon` on Darwin, `$(NIXNAME)` on Linux (default
`vm-aarch64-fusion`, so a rebuild inside the dev VM needs no arguments).

Every activation prints a `nix store diff-closures` of what is about to
change (`modules/diff.nix`) and warns when a kernel/initrd change makes a
reboot advisable (`modules/needs-reboot.nix`).

## Remote hosts

The `vm/*` targets work for any ssh-reachable NixOS host — the VMs, helium,
nitrogen — despite the prefix. They are parameterized by environment variables
(pass them on the command line or export them):

- `NIXNAME` — the nixosConfiguration to build (default `vm-aarch64-fusion`)
- `NIXADDR` — the host's address
- `NIXPORT` — ssh port (default 22)
- `NIXUSER` — ssh user (default `mich`)

| Target | Purpose |
|---|---|
| `make remote/copy` | rsync this repo into the remote host at `/nix-config` (`--delete`: stale files would be auto-imported by import-tree and break evaluation) |
| `make remote/rebuild` | `nixos-rebuild switch` on the remote host (`remote/copy` first) |
| `make remote/secrets` | rsync `~/.gnupg` and `~/.ssh` to the remote host |

## Provisioning a new host

`make remote/provision NIXADDR=… NIXNAME=…` runs
[nixos-anywhere](https://github.com/nix-community/nixos-anywhere) against any
ssh-reachable Linux (an ISO-booted VM, or a running distro it kexecs into the
installer): disko partitions per the spec in the host file, the flake config
is installed, and the machine reboots into it. Afterwards run `make
remote/secrets`. Caveat: the kexec needs enough RAM — a tiny host (~1 GB)
needs nixos-infect instead.

`packages.<system>.installer-iso` builds a minimal installer ISO with the
`keys/` public keys authorized for root, so nixos-anywhere can connect
without console steps.

### Fusion dev VM from an image

`make vm/launch` builds a VMware VMDK directly from `$(NIXNAME)` (via
nixpkgs' `vmware-image.nix` module) and drops it into
`~/Virtual Machines.localized/$(VM_NAME).vmwarevm/`, copying
`modules/hosts/dev.vmx` in as the `.vmx` template only if one isn't already
there (manual Fusion-side edits survive). First boot comes up configured:
i3 autologin as `mich`, ed25519 key authorized, hostname `dev`. Ongoing
updates inside the VM go through `make rebuild`.

`make vm/image` builds the VMDK alone and prints its `/nix/store` path.

### WSL

`nix build ".#nixosConfigurations.wsl.config.system.build.installer"` builds
the installer tarball; import it with `wsl --import`.

### Cloud images (GCE)

`make gce/image` builds a headless server GCE image (a GCS-uploadable
tarball); `make gce/upload GCE_BUCKET=<bucket> GCE_PROJECT=<project>` uploads
it and registers a Compute image (gcloud runs via `nix run`, no local
install). The image is generic — one build deploys to many instances, taking
hostname and IP from GCE metadata/DHCP at boot. Containers use podman, not
docker.

Access, in order of preference — you should never be locked out:

- **The baked `mich` key** (`keys/`) always works: `ssh mich@<ip>`.
- **OS Login** (IAM-based) works once you set the instance/project metadata
  `enable-oslogin=TRUE` and grant the caller `roles/compute.osLogin`.
- **Metadata SSH keys**, the console SSH button and `gcloud compute ssh`
  work via the guest agent. This is why the image runs with mutable users —
  a deliberate exception to the fleet's immutable-users policy, scoped to
  cloud images, so standard GCP access is always available as a fallback.

The image boots a single signed UKI: an ephemeral per-build key signs it,
and `gce/upload` enrolls the matching certificate as the image's UEFI
PK/KEK/db alongside the `UEFI_COMPATIBLE` and Confidential VM guest OS
features. Instances run with all three Shielded VM legs
(`--shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring`)
and can additionally launch as Confidential VMs
(`--confidential-compute-type=SEV` on N2D). There is no bootloader menu on
the instance: kernel/initrd changes ship as a new image.

Keep the image and its GCS object **project-private** (the `gce/upload`
defaults do this). The image bakes `mich` (authorized `keys/`, the rotated
console password hash) and trusts the cachix cache — nothing secret, but it
is identity, so don't share it publicly.

Launching an instance (adjust project/zone/network). The `enable-oslogin`
and `serial-port-enable` metadata make OS Login and boot-log access work;
the first is required to log in via OS Login, the second is invaluable for
the first boot-test:

```
gcloud compute instances create nixos-test \
    --project=<project> --zone=<zone> \
    --image=<image-name> --image-project=<project> \
    --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
    --metadata=enable-oslogin=TRUE,serial-port-enable=TRUE
# boot log:  gcloud compute instances get-serial-port-output nixos-test --zone=<zone>
```

Access is still never a lockout, but the two login paths are exclusive:
while OS Login is enabled (the metadata above) its PAM denies local users,
so IAM admins log in and sudo; `ssh mich@<ip>` with the baked key works
only on instances created with `enable-oslogin=FALSE`.

`GCE_ARCH` selects `x86_64-linux` (default, cloud standard) or
`aarch64-linux` (Graviton/Axion). The image is assembled by systemd-repart
— no VM, no KVM feature — so any builder of the target arch works: x86_64
in CI or on an x86_64 Linux host, aarch64 on the Apple-silicon
linux-builder or an arm64 runner. An instance that gets an external
IP wants the internet-facing posture layered on; the base image leaves it off
but keeps the host firewall on.

## Maintenance

| Target | Purpose |
|---|---|
| `make upp INPUT=<name>` | Bump a single flake input |
| `make history` | List system generations with dates |
| `make rollback` | Roll back to the previous system generation |
| `make gc` | Delete generations older than 7d and collect store garbage |
| `make store/verify` | Check the integrity of every store path |
| `make store/repair` | Verify with content hashing and repair broken paths |
| `make secrets/backup` | Tar `~/.ssh` + `~/.gnupg` into `backup.tar.gz.age`, encrypted under a passphrase |
| `make secrets/restore` | Decrypt `backup.tar.gz.age` back into `~` |
| `make cachix/seed` | Push the linux-builder image closure to the cachix cache |

Scheduled hygiene is built into every host: weekly GC keeping 30 days of
generations, weekly store optimise, and weekly stale-gcroot cleanup
(`modules/nix-settings.nix`, `modules/gc-roots.nix`).

## Validation

`make lint` (= `nix flake check`) runs the treefmt formatting check (nixfmt,
deadnix, shellcheck, shfmt, actionlint), the pure-eval regression tests in
`tests/` (composition wiring: profiles, GUI gating, home-manager
propagation, overlays — failures throw at eval time, nothing is built), and
evaluates every host config, catching eval breakage before deploy.

`make fmt` formats the tree; `make hooks` installs the pre-commit hooks
(fast format + hygiene on commit).

CI (`.github/workflows/check.yml`) runs the same `nix flake check` on every
push. `.github/workflows/build.yml` builds every host closure on a natively
matching runner (`ubuntu-24.04-arm` for the aarch64 VMs, `ubuntu-latest`
for wsl/helium/nitrogen, `macos-latest` for neon), so a green check means
each machine provably builds. neon's job substitutes the linux-builder
image from the cachix cache (see Binary cache below).
`.github/workflows/update-lock.yml` opens a weekly flake.lock bump PR with
the input changes in the body and dispatches check/build onto the branch.
`.github/workflows/dependency-graph.yml` submits a representative host's
closure to GitHub's dependency graph so advisories cover the deployed
system, not just the flake inputs.

## Binary cache

`https://micheloosterhof.cachix.org` is a personal cachix cache, wired as
an `extra-substituter` (with its signing key) on every host in
`modules/nix-settings.nix`. It holds artifacts cache.nixos.org lacks —
today that is one thing: the customized linux-builder VM image, an
aarch64-linux derivation that neon's CI job cannot build on a macOS runner
and a fresh Mac cannot build before it has a working builder.

- **Optional by construction**: `fallback = true` and `connect-timeout = 5`
  mean an unreachable or missing cache costs five seconds and then
  operations proceed normally (cache.nixos.org, local builds). Nothing
  hard-depends on cachix except neon's CI job, whose failure on a missing
  image is the re-seed signal.
- **Seeding**: `make cachix/seed` builds the builder image (via the Mac's
  own builder) and pushes its closure (~3 GiB). Run it after a flake.lock
  bump changes the image. Pushing needs the cachix CLI authenticated once:
  `nix run nixpkgs#cachix -- authtoken <token>`.
- **Reading needs no auth** — the cache is world-readable, so CI pulls
  without secrets. The `CACHIX_TOKEN` repo secret exists but is unused;
  it's reserved for selective CI pushing later. Free-tier storage is 5 GB,
  so don't push whole host closures.

## Building Linux artifacts on the Mac

Building aarch64-linux derivations (e.g. `make vm/image`) on aarch64-darwin
needs a Linux builder. The Mac config uses nix-darwin's `nix.linux-builder`
(`modules/hosts/neon.nix`): a NixOS aarch64-linux VM under
launchd, `ephemeral = true` so it doesn't persist state between boots.

- The customized builder (8 cores / 32 GB / 100 GB) cache-misses against
  cache.nixos.org. A fresh Mac substitutes it from the cachix cache when
  seeded (see Binary cache above); with the cache empty, a first activation
  must use the default variant, since only a working builder can build the
  customized image.
- "failed to start SSH connection to linux-builder" means the builder VM is
  down (ephemeral builders don't restart after a crash). Revive with
  `sudo launchctl kickstart -k system/org.nixos.linux-builder`, then wait:
  ephemeral init recreates the disk image and takes minutes; probe with
  `nc -z localhost 31022` rather than restarting again mid-boot. Debug with
  `sudo ssh linux-builder`.
- This setup requires `nix.enable = true` (nix-darwin owns nix.conf and the
  daemon). Switching to determinate-nix would need `nix.enable = false` and
  a different builder strategy (e.g. nix-rosetta-builder).

## Gotchas

- `flake.lock` regenerates aggressively — `nix flake lock` re-pins branch
  refs to current tips for `nixpkgs`, `nixpkgs-unstable`, `darwin`. That's a
  real version bump, not a no-op. Call it out when committing.
- A `nixpkgs-unstable` bump can silently demand from-source builds of the
  overlay packages (`modules/overlays.nix`). Before committing one, check
  the new outPaths exist on cache.nixos.org
  (`nix path-info --store https://cache.nixos.org <outPath>`) — zed-editor
  has shipped without a darwin binary for days at a time.
- `nix flake check` prints `warning: unknown flake output 'modules'` —
  inherent to exposing `flake.modules` as an output; cosmetic.
