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
oxygen — despite the prefix. They are parameterized by environment variables
(pass them on the command line or export them):

- `NIXNAME` — the nixosConfiguration to build (default `vm-aarch64-fusion`)
- `NIXADDR` — the host's address
- `NIXPORT` — ssh port (default 22)
- `NIXUSER` — ssh user (default `mich`)

| Target | Purpose |
|---|---|
| `make vm/copy` | rsync this repo into the remote host at `/nix-config` (`--delete`: stale files would be auto-imported by import-tree and break evaluation) |
| `make vm/rebuild` | `nixos-rebuild switch` on the remote host (`vm/copy` first) |
| `make vm/update` | Bump `flake.lock` to branch tips, then copy + rebuild the remote host |
| `make vm/secrets` | rsync `~/.gnupg` and `~/.ssh` to the remote host |

## Provisioning a new host

`make vm/provision NIXADDR=… NIXNAME=…` runs
[nixos-anywhere](https://github.com/nix-community/nixos-anywhere) against any
ssh-reachable Linux (an ISO-booted VM, or a running distro it kexecs into the
installer): disko partitions per the spec in the host file, the flake config
is installed, and the machine reboots into it. Afterwards run `make
vm/secrets`. Caveat: the kexec needs enough RAM — a tiny host (oxygen, ~1 GB)
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

`make wsl` builds the installer tarball; import it with `wsl --import`.

## Maintenance

| Target | Purpose |
|---|---|
| `make upp INPUT=<name>` | Bump a single flake input |
| `make history` | List system generations with dates |
| `make rollback` | Roll back to the previous system generation |
| `make gc` | Delete generations older than 7d and collect store garbage |
| `make store/verify` | Check the integrity of every store path |
| `make store/repair` | Verify with content hashing and repair broken paths |
| `make secrets/backup` | Tar `~/.ssh` + `~/.gnupg` into `backup.tar.gz` |
| `make secrets/restore` | Untar `backup.tar.gz` back into `~` |

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
push. `.github/workflows/dependency-graph.yml` submits a representative
host's closure to GitHub's dependency graph so advisories cover the deployed
system, not just the flake inputs.

## Building Linux artifacts on the Mac

Building aarch64-linux derivations (e.g. `make vm/image`) on aarch64-darwin
needs a Linux builder. The Mac config uses nix-darwin's `nix.linux-builder`
(`modules/hosts/neon.nix`): a NixOS aarch64-linux VM under
launchd, `ephemeral = true` so it doesn't persist state between boots.

- The customized builder (8 cores / 32 GB / 100 GB) cache-misses against
  cache.nixos.org, so a first activation must use the default variant; only
  a working builder can build the customized image.
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
