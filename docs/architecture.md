# Architecture

How this flake is organized: the dendritic pattern, the host-shape options, and
the two output families.

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

## Host-shape options

Two orthogonal axes describe a host:

- **Platform (what it runs on)** — `flake.modules.nixos.{fusion,utm,apple-vm}`:
  hypervisor drivers, guest tools, host-integration glue. Chosen by each host
  file at composition time (imports cannot depend on `config`).
- **Profile + capabilities (what it's for)** — NixOS options declared in
  `modules/profile.nix`:

```nix
my.profile    = "workstation" | "server";   # sets capability defaults
my.gui.enable = bool;                        # workstation: on, server: off
```

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

Three fundamentally different build products, not to be forced onto one axis:

1. **Bootable hosts** — `nixosConfigurations` / `darwinConfigurations`, one
   file each under `modules/hosts/`. Currently: vm-aarch64-fusion (VMware,
   workstation), vm-aarch64-utm (UTM, workstation), vm-aarch64-apple (Apple
   Virtualization.framework "container machine", workstation but headless by
   platform), wsl (server), helium and oxygen (servers), neon (darwin).

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
   `flake.modules.nixos.gce` aggregate (the upstream google-compute-image
   module + eth0 DHCP + host firewall + gcloud) doubles as a platform a
   per-host cloud config could compose later. The internet-facing posture
   (bogons, tighter rules) is layered per-deployment, not baked.

## Validation

`nix flake check --no-build` runs nixfmt, deadnix and the pure-eval tests in
`tests/default.nix`, which assert the composition wiring (profiles, GUI
gating incl. the apple-vm mkForce case, HM propagation, overlays, the
container derivation). The migration itself was verified by derivation
equality: wsl and the mac byte-identical across the conversion;
fusion/utm equivalent (identical package sets; only merge order differs).

## Unvalidated

- **apple-vm** has never been booted; the virtio module set and `hvc0`
  console are a first cut (marked in `modules/platforms/apple-vm.nix`).
- **container-server** builds to a correct rootfs (verified: `/init`,
  `activate`, nix store) but running systemd as PID 1 under each runtime is
  untested.
- **gce-image** builds (x86_64 green in CI) but has not been booted on GCE;
  the guest-agent, OS Login, DHCP and serial-console wiring come from the
  upstream `google-compute-image` module but are unverified against a real
  instance. The image is legacy-BIOS (GRUB); Shielded VM (Secure Boot) would
  need `virtualisation.googleComputeImage.efi = true`.

## Deferred

- Expanding `container-server` beyond the bare base (users, ssh, services).
- A `my.gui.compositor` choice — declared only when sway is wired
  cross-platform; Fusion keeps its working sway boot specialisation.
- A baked-entrypoint OCI wrapper (`dockerTools`) for turnkey `docker load`.
- An `appliance` profile, when it has a concrete definition.
- Colocating home-manager feature halves with their system halves (the
  dendritic payoff), progressively as files are touched.
