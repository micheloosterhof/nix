# nixos-config

Personal NixOS / nix-darwin / WSL configurations, all driven by one flake.
Forked from [mitchellh/nixos-config](https://github.com/mitchellh/nixos-config).
The active user is `mich`.

Hosts: `neon` (nix-darwin), `vm-aarch64-{fusion,utm,apple}`
(NixOS workstation VMs), `wsl`, and the headless servers `helium` and
`oxygen`. The flake also builds a `container-server` rootfs tarball and a
provisioning `installer-iso`.

All operations go through `make`. Run `make` with no arguments for the menu.

## Quickstart

### macOS (Apple Silicon)

First-time activation:

```
sudo nix --extra-experimental-features 'nix-command flakes' run nix-darwin -- \
    switch --flake .#neon
```

After that:

```
make rebuild        # rebuild + activate
make test           # build + activate without persisting a boot entry
```

This enables `nix.linux-builder` so the Mac can build aarch64-linux
derivations through a managed NixOS VM on demand.

### Linux dev VM (VMware Fusion)

The flake builds a Fusion VMDK directly from the configuration — no
boot-from-ISO bootstrap:

```
make vm/launch
open ~/Virtual\ Machines.localized/dev.vmwarevm
```

First boot autologins to `mich` in i3, accepts your ed25519 key for SSH,
sets hostname `dev`. For ongoing updates from inside the VM: `make rebuild`.

### WSL

```
make wsl
```

Produces a tarball you import with `wsl --import`.

### Servers

Fresh installs go through nixos-anywhere + disko:

```
make vm/provision NIXADDR=<address> NIXNAME=<host>
```

## Documentation

- [docs/architecture.md](docs/architecture.md) — how the flake is organized
- [docs/operations.md](docs/operations.md) — build, deploy, provisioning, maintenance
- [AGENTS.md](AGENTS.md) — conventions, for humans and agents alike

## License

Inherited from upstream. See `LICENSE`.
