# Architecture

How this flake is organized: the dendritic pattern, the axes that describe a
system, and the output families.

## The dendritic pattern

The flake is a [flake-parts](https://flake.parts) configuration whose modules
are auto-imported from `modules/` by
[import-tree](https://github.com/vic/import-tree) — the
[dendritic pattern](https://github.com/mightyiam/dendritic). Every file under
`modules/` is a *top-level* (flake-parts) module implementing one feature; file
paths carry no mechanical meaning and files can be moved or split freely
(paths containing `/_` are ignored by the auto-import).

Lower-level NixOS/nix-darwin modules live as named aggregates under
`flake.modules.<class>.<name>` (declared in `modules/modules-option.nix`,
type `deferredModule`). Multiple files defining the same name merge — e.g.
`overlays.nix`, `nix-settings.nix`, `home.nix`, `profile.nix` and `gui.nix`
all contribute to `flake.modules.nixos.base`. A feature that spans classes
assigns the same value to several aggregates (see `nix-settings.nix`,
contributing to `nixos.base`, `nixos.container` and `darwin.base`).

Hosts are composed in `modules/hosts/<name>.nix`, one file per system:

```nix
flake.nixosConfigurations.vm-aarch64-fusion = inputs.nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  modules = [
    config.flake.modules.nixos.base    # nix settings, overlays, HM, profile/gui
    config.flake.modules.nixos.vm      # headless Linux VM base
    config.flake.modules.nixos.fusion  # VMware platform integration
    ../../users/mich/nixos.nix
    { my.profile = "workstation"; }
    { <this instance's disks and filesystems, inline> }
    ...
  ];
};
```

Each host file is self-contained: composition plus that instance's hardware
(disks, filesystems, initrd modules). Unused hardware templates are parked
alongside with an underscore prefix (ignored by the auto-import). The only
plain (non-top-level) files left are `users/mich/` — a blessed exception;
they migrate into feature files progressively when touched.

## The axes of a system

Every system is a composition along orthogonal axes:

**system = shared baseline + substrate + role + exposure + (identity | nothing)**

- **Substrate (what it runs on)** — `flake.modules.nixos.{fusion,utm,apple-vm}`:
  hypervisor drivers, guest tools, host-integration glue. Chosen by each host
  file at composition time (imports cannot depend on `config`). GCE, WSL and
  the container runtime are substrates too, currently encoded ad hoc
  (`gce.nix`, inline in `wsl.nix`, `container.nix`).
- **Role (what it's for)** — NixOS options declared in `modules/profile.nix`:

```nix
my.profile    = "workstation" | "server";   # sets capability defaults
my.gui.enable = bool;                        # workstation: on, server: off
```

- **Identity (who it is)** — *singleton* configs are owned by exactly one
  machine and set `my.hostnameGuard` beside their `networking.hostName`
  (refusing wrong-host activation); *templates* (the image outputs) bake no
  identity and receive it after deployment. The two convert: a template plus
  an identity overlay is a singleton (GCE metadata names an instance at
  boot), and an image stamped from a singleton carries its identity into
  every clone (the fusion VMDK boots pre-named `dev`).
- **Exposure (where it faces)** — substrate implies a default (a NATted VM
  is not internet-facing; a TransIP KVM is), but position-dependent controls
  are currently composed by hand: nitrogen composes `bogons`; the GCE image
  deliberately bakes no posture. Zero-trust rule: exposure is *not* a
  security tier — hardening, key-only ssh and sudo restrictions are
  unconditional on every machine; exposure only gates controls whose
  *correctness* depends on network position (bogon source-drops are wrong,
  not merely unneeded, where legitimate traffic has RFC1918 sources).

Architecture (arm/intel) is deliberately **not** an axis: `system` is a build
parameter, and nothing branches on it (the GCE image builds both arches from
one definition).

The fleet along these axes:

| system | arch | substrate | role | exposure | identity | output |
|---|---|---|---|---|---|---|
| vm-aarch64-fusion | arm | Fusion | workstation | lan (NATted) | singleton ("dev") | config + vmdk image |
| vm-aarch64-utm | arm | UTM | workstation | lan (NATted) | singleton ("dev-utm") | config |
| vm-aarch64-apple | arm | Apple Virt | workstation | lan (NATted) | singleton ("dev-apple") | config |
| wsl | intel | WSL | server | lan (NATted) | unnamed instance | config + installer tarball |
| helium | intel | metal/home | server | lan (home) | singleton | config |
| nitrogen | intel | TransIP KVM | server | internet | singleton | config |
| neon | arm | Mac metal | workstation | lan | singleton | config (darwin) |
| gce-image | both | GCP | server | per-deploy (unbaked) | template | package |
| container-server | arm/intel | container runtime | server | (host's) | template | package |
| installer-iso | both | anywhere | (tool) | — | template | package |

Priorities make the layering work: the profile sets `my.gui.enable` with
`mkDefault` (1000), a host overrides with a plain assignment (100), and a
platform that cannot have a GUI forces it off with `mkForce` (50) — the
apple-vm platform does exactly that, so even `profile = "workstation"` stays
headless there.

Cross-cutting interactions resolve themselves:

- `gui.nix` and platform GUI glue (Fusion's clipboard, the sway boot option;
  UTM's SPICE agent) self-gate on `my.gui.enable`.
- home-manager reads the same signal via `osConfig.my.gui.enable or false`
  (`or false` covers darwin, where `my.*` isn't declared) to gate i3, rofi,
  chromium, the pointer cursor and Ghostty-on-Linux.

## Output families

Four fundamentally different build products, not to be forced onto one axis.
The identity axis shows up here structurally: singletons are
`nixosConfigurations`/`darwinConfigurations`, templates are `packages`.
(`flake.templates` — the per-project dev-shell scaffolds under `templates/` —
are unrelated to the fleet.)

1. **Bootable hosts** — `nixosConfigurations` / `darwinConfigurations`, one
   file each under `modules/hosts/`. Currently: vm-aarch64-fusion (VMware,
   workstation), vm-aarch64-utm (UTM, workstation), vm-aarch64-apple (Apple
   Virtualization.framework "container machine", workstation but headless by
   platform), wsl (server), helium and nitrogen (servers), neon (darwin).

2. **Container images** — `packages.<linux-system>.container-server`
   (`modules/container.nix`): NixOS as a root-filesystem tarball on top of
   nixpkgs' upstream `profiles/docker-container.nix`. One OCI artifact;
   docker, podman, k8s and Apple's pure `container` are four *runtimes* for
   it, not four targets. Consume with
   `docker import result/tarball/*.tar.xz <name>` and run `/init`.
   Deliberately a bare base (no user, ssh or services yet) — workloads get
   layered on next. Starts at `stateVersion = "26.05"` (new artifact family,
   no 2020-era state to preserve).

3. **Cloud images** — `packages.<linux-system>.gce-image`
   (`modules/gce.nix`): a headless server-profile GCE disk image, built for
   both x86_64 and aarch64. Generic and reusable — hostname and IP come from
   GCE metadata/DHCP at boot, so one image deploys to many instances. The
   `flake.modules.nixos.gce` aggregate (the upstream google-compute-config
   module + systemd-repart image assembly + a signed-UKI Secure Boot chain +
   eth0 DHCP + host firewall + gcloud) doubles as a platform a per-host
   cloud config could compose later. The internet-facing posture (bogons,
   tighter rules) is layered per-deployment, not baked.

4. **Installer ISO** — `packages.<linux-system>.installer-iso`
   (`modules/installer-iso.nix`): a minimal installer image with the `keys/`
   public keys authorized for root, so nixos-anywhere
   (`make remote/provision`) can reach a fresh machine without console
   steps.

## Validation

`make lint` (`nix flake check --all-systems`) builds the treefmt formatting
check (nixfmt, deadnix, shellcheck, shfmt, actionlint) and runs the pure-eval
tests in `tests/default.nix`, which assert the composition wiring (profiles,
GUI gating incl. the apple-vm mkForce case, hostname-guard coverage, HM
propagation, overlays, the container derivation). With `--no-build` only the
eval tests still report — the formatting check is skipped, which is why
formatting drift can pass locally and fail in CI. The migration itself was verified by derivation
equality: wsl and the mac byte-identical across the conversion;
fusion/utm equivalent (identical package sets; only merge order differs).

## Unvalidated

- **apple-vm** has never been booted; the virtio module set and `hvc0`
  console are a first cut (marked in `modules/platforms/apple-vm.nix`).
- **container-server** builds to a correct rootfs (verified: `/init`,
  `activate`, nix store) but running systemd as PID 1 under each runtime is
  untested.
- **gce-image (aarch64)** builds in CI but has never been launched on an
  arm instance. The x86_64 image is launch-verified on a Shielded + SEV
  Confidential VM (Secure Boot enabled with the enrolled custom cert,
  vTPM, integrity monitoring, OS Login, serial console); the aarch64
  variant shares the composition but none of that is confirmed on T2A.

## Deferred

- Expanding `container-server` beyond the bare base (users, ssh, services).
- A `my.gui.compositor` choice — declared only when sway is wired
  cross-platform; Fusion keeps its working sway boot specialisation.
- A baked-entrypoint OCI wrapper (`dockerTools`) for turnkey `docker load`.
- An `appliance` profile, when it has a concrete definition.
- Colocating home-manager feature halves with their system halves (the
  dendritic payoff), progressively as files are touched.
