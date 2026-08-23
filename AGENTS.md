ABOUTME: Project conventions and orientation for AI coding agents working in this repo.
ABOUTME: Humans should also read this — start here, then the docs/ it points at.

# AGENTS.md

Personal NixOS / nix-darwin / WSL configurations for user `mich`. Originally
forked from `mitchellh/nixos-config`, since restructured around the dendritic
pattern (flake-parts + import-tree).

The detailed maps live in `docs/`:

- **[docs/architecture.md](docs/architecture.md)** — how the flake is
  organized: the dendritic pattern, `flake.modules.<class>.<name>`
  aggregates, the profile/platform axes, the output families. Read it before
  restructuring anything.
- **[docs/operations.md](docs/operations.md)** — build, deploy,
  provisioning, the Mac's Linux builder, the cachix binary cache, and the
  gotchas around `flake.lock`.
- **[docs/build-venues.md](docs/build-venues.md)** — which builds can run
  where, what CI should own, and the rule that keeps every machine
  updatable from a local checkout with GitHub unreachable.

## Repo layout

```
flake.nix                # inputs + one-line mkFlake over import-tree ./modules
modules/                 # every .nix here is a flake-parts module, auto-imported
  <feature>.nix          # one feature per file; merges into flake.modules.<class>.<name>
  platforms/             # platform aggregates: fusion, utm, apple-vm
  hosts/                 # one file per system, composing aggregates + instance hardware
users/mich/              # nixos/darwin/home-manager.nix + dotfiles (blessed non-module exception)
keys/                    # *.pub files authorized for mich + root on every NixOS host
templates/               # per-project dev-shell flake templates
tests/                   # pure-eval regression tests (the eval-tests flake check)
docs/                    # architecture + operations
Makefile                 # entry point for all operations (`make` for the menu)
```

File paths under `modules/` carry no mechanical meaning; paths containing
`/_` are ignored by the auto-import (used to park unused hardware
templates).

Current systems: `vm-aarch64-fusion`, `vm-aarch64-utm`, `vm-aarch64-apple`
(workstation VMs), `wsl` (server), `helium`, `nitrogen` (headless servers),
`neon` (nix-darwin), plus the `container-server` rootfs-tarball
package and the `installer-iso` package.

## Build / deploy

All operations go through the `Makefile`; run `make` for the full menu.
Day-to-day: `make rebuild` (build + activate the local host), `make test`
(activate without a boot entry), `make lint` (`nix flake check`), `make fmt`.
Remote and provisioning workflows are in `docs/operations.md`.

There is no build-level test suite — "test" means a trial activation.
`make lint` runs the formatting checks, the pure-eval wiring tests in
`tests/`, and evaluates every host config. CI runs the same check on every
push.

## Conventions

- **User**: every system uses `mich`.
- **Two nixpkgs inputs**: `nixpkgs` (stable, currently `nixos-26.05`) and
  `nixpkgs-unstable`. `modules/overlays.nix` cherry-picks a few packages
  from unstable. Prefer stable unless there's a reason.
- **No channels.** `modules/nix-settings.nix` pins `nix.registry.nixpkgs`
  and `nix.nixPath` to the stable flake input on every host, so `<nixpkgs>`,
  `nix-shell -p`, and `nixpkgs#…` resolve to the pinned release. Don't
  reintroduce `nix-channel`.
- **Package placement**: cross-platform CLI tools → `home.packages` in
  `users/mich/home-manager.nix` (darwin-only ones in its `isDarwin` branch);
  Linux system-level packages → the `vm`/`server` aggregates; macOS GUI apps
  and brew-only formulae → `users/mich/darwin.nix` homebrew. Ad-hoc tools →
  `nix shell nixpkgs#…` or per-project flakes + direnv, never `nix-env -iA`.
  Don't list a package in more than one layer.
- **Naming**: VMs are `vm-<arch>-<hypervisor>`; servers get element names
  (helium, nitrogen).
- **Shell**: bash/zsh only.
- **Commits**: imperative, lowercase, terse — match the existing log
  (`remove cruft`, `set timezone`). No AI attribution, no
  `Co-Authored-By: Claude`, no "Generated with Claude Code".
- **Branch**: small changes go directly on `main`; larger work gets a
  branch.

## Things to be careful with

- `flake.lock` regenerates aggressively; a lock refresh is a real version
  bump. Details and the unstable-overlay cache caveat: `docs/operations.md`.
- neon has no CI build job — only full-config evaluation (the eval-tests
  check) — so a darwin package that evaluates but fails to build surfaces
  at `make rebuild` (`docs/build-venues.md`).
- Homebrew (darwin) runs `onActivation.cleanup = "none"`, so ad-hoc `brew
  install` survives activation; the cask/brew lists in
  `users/mich/darwin.nix` are not yet exhaustive.
- The Mac must keep `nix.enable = true` (nix-darwin owns nix.conf) or the
  Linux builder asserts — see `docs/operations.md`.
