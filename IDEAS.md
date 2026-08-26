# IDEAS.md — triaged backlog

Sorted by actionability (triage 2026-08-26), no longer by survey.
Nothing was deleted in the sort: every idea from the survey sections is
below, verbatim, with its source in parentheses. The survey log at the
bottom records what was surveyed when; the "decided against" section
keeps the explicit don't-adopt verdicts and the surveys' own skip notes.

---

# 1. Specced and ready — Tier-1 batch (2026-08-20)

The cheap wins scattered across the surveys, checked against the repo
and turned into concrete changes. None is implemented today: `zramSwap`,
`journald`, `initrd.systemd`, `useNetworkd`, `nix-output-monitor`,
`programs.nh`, `direnvrc`, `intent-to-add`, `warn-dirty`,
`builders-use-substitutes` and `FailureAction` appear nowhere in the repo
outside this file.

Two source bullets turned out to be wrong or more expensive than
advertised — see nh and registry pinning. Each item below is one commit.

## Batch A — no decision to make

**1. Two nix.settings keys** (`modules/nix-settings.nix`, in the `settings`
block around line 40). Add:

```nix
# The repo is worked on dirty most of the time; the warning on every
# build is noise.
warn-dirty = false;
# Remote builders substitute from the caches themselves instead of
# receiving every dependency over ssh from the client.
builders-use-substitutes = true;
```

`builders-use-substitutes` only bites on neon (the one host with
`nix.buildMachines`), but it is a client-side setting and harmless on the
rest, so it stays in the shared block. Test: one eval assertion per key
alongside the existing `testSubstituterFallback` in `tests/default.nix`.

**2. `git add --intent-to-add` before local builds** (`Makefile`). A
path-flake in a git worktree only sees tracked files, so a newly written
`modules/foo.nix` is invisible to `nix build` until it is staged — the
"path does not exist" gotcha. Add a helper target and make the four local
targets depend on it:

```make
# A path flake only copies git-tracked files, so a new module is invisible
# to the build until it is at least intent-to-add staged.
.PHONY: stage
stage:
	@git add --intent-to-add .
```

`rebuild`, `test`, `build`, `check` gain `stage` as a prerequisite. Safe
against junk: `--intent-to-add` honours `.gitignore`, which already covers
`result`, `backup.tar.gz*` and `iso/nixos.iso`. Not the remote targets —
`remote/copy` rsyncs the worktree and does not care. No test (Makefile).

**3. Cap journal growth** (`modules/vm.nix` and `modules/server.nix`, or
once on the shared base). `services.journald.extraConfig = "SystemMaxUse=1G"`.
The VMs run a ~40 GiB virtual disk and the servers are small; the default
cap is 10% of the filesystem, which is a lot of disk spent on logs nobody
reads. Note `server` is composed into the GCE image too (`flake.lib.gceSystem`
= base + server + gce), which is if anything a stronger reason to cap.
Test: an eval assertion on one VM and one server.

**4. zram swap** (`modules/vm.nix`). `zramSwap.enable = true`. Compressed
RAM-backed swap so a big `nix build` in the guest degrades instead of
OOM-killing. Take zram alone — Mic92's separate zswap module on top of it
is a known anti-pattern. Leave the servers out for now: helium has 32 GB
and nitrogen's workload is known. Test: eval assertion on fusion.

**5. nix-output-monitor on the image targets** (`Makefile`, `home.packages`).
Add `pkgs.nix-output-monitor` to the `fullTools` list in
`users/mich/home-manager.nix`, then swap `nix build` → `nom build` in
`vm/image` (line 222) and `gce/image` (line 247). Verified: `nom build
--no-link --print-out-paths` puts only the store path on stdout, so the
`$(...)` capture in `vm/launch` and `gce/upload` keeps working unchanged.
The `*-rebuild` targets are a separate question — piping them needs
`--log-format internal-json -v |& nom --json`, and if nh (item 9) lands it
already prints an nom-style tree, so leave those alone. No test.

**6. Offline-aware direnv** (`users/mich/home-manager.nix`, in the existing
`programs.direnv` block). On a plane or a dead network, `use flake` tries to
evaluate and fetch, and hangs. nix-direnv exposes a supported opt-out:

```nix
stdlib = ''
  # No default route: serve nix-direnv's cached environment instead of
  # evaluating the flake, which would block on a fetch.
  if ! ${if isDarwin then "route -n get default" else "ip route get 1.1.1.1"} >/dev/null 2>&1; then
    nix_direnv_manual_reload
  fi
'';
```

Verified against the pinned versions: home-manager writes `stdlib` to
`$XDG_CONFIG_HOME/direnv/direnvrc`; direnv sources `direnv/lib/*.sh` (where
HM puts nix-direnv) *before* `direnvrc`, so `nix_direnv_manual_reload` is
defined by then. The route check has to branch per-OS — `ip` does not exist
on darwin. Test: none worth writing (shell text in a dotfile).

**7. gitconfig defaults** (`users/mich/home-manager.nix`, `programs.git.settings`).
The surveys list two sets; after subtracting what is already configured and
what fights an existing decision, this is what is left:

```nix
rebase.autosquash = true;      # `commit --fixup` lands without --autosquash
rebase.updateRefs = true;      # stacked branches follow a rebase
diff.algorithm = "histogram";
branch.sort = "-committerdate";
core.untrackedCache = true;    # default is "keep"; true actually enables it
fetch.writeCommitGraph = true; # default false; core.commitGraph is already on
commit.verbose = true;         # diff in the commit-message editor
help.autocorrect = 10;
am.threeWay = true;
```

plus aliases `fpush = "push --force-with-lease"`, `uncommit = "reset --soft
HEAD^"`, and `checkout-pr` (fetch `pull/$N/head`).

Deliberately excluded: `core.commitGraph` (has defaulted to true since git
2.24 — adding it is a no-op); the `gh auth git-credential` helper (fights the
existing split of osxkeychain on darwin / SSH url-rewrite on Linux, and
`programs.gh.gitCredentialHelper.enable = false` is a deliberate setting);
`gpg.format = "ssh"` (a real decision against the configured GPG key
523D5DC389D273BC, not a Tier-1 one-liner); `[include] ~/.gitconfig.local`
(the config is the source of truth here, and HM already writes the file).
Conditional per-directory identity is worth having the day work and personal
repos share a machine — not yet. No test.

## Batch B — one decision each

**8. Pin every flake input into the registry** (`modules/nix-settings.nix`).
The claimed cost is "~700 MB of source trees in the closure". Measured on
the current lock:

| input | source closure |
| --- | --- |
| nixpkgs | 196 MiB (already pinned) |
| nixpkgs-unstable | 201 MiB |
| home-manager | 6 MiB |
| the other eight | under 1 MiB each |

So the real tradeoff is nixpkgs-unstable and nothing else: pinning the nine
small inputs costs about 7 MiB. Proposal — pin everything except
nixpkgs-unstable everywhere, and reconsider unstable separately:

```nix
registry = lib.mapAttrs (_: flake: { inherit flake; }) (
  lib.filterAttrs (n: v: n != "nixpkgs-unstable" && lib.isType "flake" v) inputs
);
```

with `nixPath` derived the same way. `flake-registry = ""` (blank the global
registry so nothing silently resolves to an unpinned upstream) is the second
half and can ride along. Decision: whether to accept 201 MiB on the lean
artifacts (`my.tools.full = false` — the GCE image — and the container
tarball) for `nix run nixpkgs-unstable#…` to work offline. Test: an eval
assertion that the registry has an entry per input and that the GCE closure
does not gain the unstable source.

**9. nh as the rebuild/GC frontend.** Two corrections to the survey bullet:

- **`programs.nh` does not exist in nix-darwin.** Checked the pinned
  `nix-darwin-26.05` source: no `modules/programs/nh.nix`, no `programs.nh`
  anywhere. It is a NixOS module and a home-manager module. So on neon nh
  arrives via home-manager (which does support it, with `darwinFlake` and a
  launchd clean agent); on the NixOS hosts it is the system module.
- **`nh clean` and `nix.gc.automatic` are mutually exclusive.** The NixOS
  module warns when both are on, home-manager likewise. `modules/nix-settings.nix`
  sets `gc.automatic = true` on every host, so adopting `nh clean` means
  deleting that block and moving the policy to
  `programs.nh.clean.extraArgs = "--keep 5 --keep-since 20d"`. That is the
  actual win — keep-count *and* keep-age, which `nix.gc.options` cannot
  express — but it is a swap, not an addition.

`NH_FLAKE` is per-host (the repo is at `~/src/nix` on neon and `/nix-config`
on a remote-rebuilt VM), so either leave `flake` unset and rely on cwd, or
set it per host file. `make rebuild`/`make gc` keep their names and call nh
underneath. Decision: whether to hand GC scheduling to nh. Test: an eval
assertion that exactly one of the two GC mechanisms is enabled per host.

**10. sshd-or-reboot watchdog** (`modules/server.nix`):

```nix
# A headless box whose sshd fails at boot is unreachable; reboot instead
# of sitting there.
systemd.services.openssh = {
  wantedBy = [ "boot-complete.target" ];
  unitConfig.FailureAction = "reboot";
};
```

Decision is scope, and it matters: `server` is also composed into the GCE
image, where a persistent sshd failure would turn into a reboot loop that
costs money and hides the cause. Options: put it on `server` and accept
that; put it on the two pet servers' host files only (helium, nitrogen);
or put it on `server` and override it off in `modules/gce.nix`. Prefer the
host files — nitrogen is the machine this is actually insurance for (remote,
non-standard ssh port 3333, nothing else to reach it by except the tailnet).
Test: eval assertion on whichever hosts get it.

## Batch C — needs a VM boot test, not just an eval

**11. systemd initrd** (`modules/vm.nix`): `boot.initrd.systemd.enable = true`.
Drop-in on paper — no LUKS, no custom initrd scripts in the repo — but it
replaces the whole early boot path, so it gets verified by booting the
fusion VM, not by `nix flake check`. Do it before item 12; if both land at
once and the VM does not come back, there are two suspects.

**12. networkd with a mac-based DHCP identifier** (`modules/vm.nix`,
replacing `networking.useDHCP = true` at line 26):

```nix
networking.useNetworkd = true;
systemd.network.networks."10-uplink" = {
  matchConfig.Type = "ether";           # no interface names: Fusion/UTM/VZ
  networkConfig.DHCP = "yes";
  dhcpV4Config.ClientIdentifier = "mac"; # stable lease across rebuilds
};
```

`matchConfig.Type = "ether"` (Mic92's utm-vm) is stronger than phaer's
`en* eth*` name glob and drops the "hypervisor NICs get unpredictable
enpXsY names" problem the current comment describes. The mac-based client
identifier is the payoff: the VM keeps its NAT lease, which is what the
hardcoded `dev` → `192.168.85.146` entry in `programs.ssh` depends on today.
Pair it with `systemd.services.systemd-networkd.stopIfChanged = false` (and
the same for resolved) so a `nixos-rebuild switch` over ssh does not cut the
network mid-switch. Interacts with `modules/dns.nix` (resolved + DoT), which
networkd integrates with cleanly. Verify by booting fusion and utm and
confirming the lease survives two rebuilds.

## Suggested order

A1–A7 in any order, one commit each — all eval-only, all verifiable with
`make lint`. Then B8/B9/B10, each carrying its decision. Then C11, boot the
VM, then C12, boot the VM again.

## Source bullets absorbed into this batch (kept for provenance)

The survey bullets the batch items were specced from, verbatim. The
batch items above supersede these where they disagree (see the nh and
registry-pinning corrections).

- **Git defaults worth stealing** — from his `minimal/hm.nix` (traxys), all
  absent here, each a one-liner that helps a rebase-heavy workflow
  `rebase.autosquash` + `rebase.updateRefs` (stacked branches follow along),
  `diff.algorithm = histogram`, `branch.sort = "-committerdate"`,
  `core.untrackedCache`, `fetch.writeCommitGraph` + `core.commitGraph`
  (faster status/log in big repos), alias `fpush = push --force-with-lease`.
  → batch A7.
- **nix-output-monitor for builds** — traxys patches nixos-rebuild to call
  `nom build` (`minimal/nom-rebuild.patch`); the 90% version with zero
  maintenance is adding `nix-output-monitor` to `home.packages` and piping
  in the Makefile (`... |& nom`, or `nom build` where targets run
  `nix build`, e.g. `vm/image`, `wsl`). → batch A5.
- **nh as the rebuild/GC frontend** (Misterio77, EmergentMind, wimpysworld —
  three configs independently). `programs.nh` exists on both NixOS and
  nix-darwin: `nh os|darwin|home switch` wraps rebuilds with nom-style build
  trees and an nvd closure diff; `nh clean all --keep 5 --keep-since 20d`
  expresses keep-count *and* keep-age, which `nix.gc.options` can't. Slots
  behind `make switch`/`make gc` without changing the interface. → batch
  B9, with two corrections (no nix-darwin module; mutually exclusive with
  `nix.gc.automatic`).
- **Pin every flake input into the registry, and blank the global one**
  (Misterio77, EmergentMind, srid, wimpysworld — four configs). We pin only
  `nixpkgs`. `nix.registry = lib.mapAttrs (_: flake: { inherit flake; })
  (lib.filterAttrs (_: lib.isType "flake") inputs)` + matching `nixPath` +
  `flake-registry = ""` makes every `nix run/shell <input>#…` resolve to the
  locked rev — deterministic, offline-capable, no surprise second nixpkgs
  download. wimpysworld's caveat to keep: pinning inputs embeds their source
  trees in the closure (~700 MB), so pin everything on workstations but only
  self/nixpkgs on the container tarball and VM images. → batch B8, with
  the measured closure numbers.
- **Small nix.settings from people who build nix** (Mic92, EmergentMind):
  `warn-dirty = false`, `builders-use-substitutes = true` (remote builder
  fetches from cache directly instead of copy-via-Mac; free win for the
  existing linux-builder). → batch A1.
- **Offline-aware direnv** (Mic92 `home/.direnvrc`): checks default route +
  a 1s ping; when offline sets `_nix_direnv_manual_reload=1` so nix-direnv
  serves the stale env instead of trying to evaluate/fetch on a plane.
  Copy verbatim. → batch A6.
- **VM/host one-liners** (Mic92, machines/, nixosModules/): `pkgs.ghostty.terminfo`
  (terminfo output only) in the VM's systemPackages so ghostty-over-SSH
  works — the lightweight version of the srvos mixins-terminfo idea in the
  ryan4yin survey; `services.journald.extraConfig = "SystemMaxUse=1G"` (cap
  journal growth on small VM disks); `zramSwap.enable = true` (take zram
  alone — his separate zswap module on top is a known anti-pattern);
  `systemd.services.systemd-networkd.stopIfChanged = false` (+ resolved) so
  a `nixos-rebuild switch` over SSH doesn't cut the network under you;
  `services.getty.autologinUser` on the throwaway VM;
  `services.dbus.implementation = "broker"`. → journald/zram/stopIfChanged
  are batch A3/A4/C12; the rest stayed in section 2.
- **sshd-or-reboot watchdog** (Mic92 machines/bernie): `systemd.services.openssh
  = { wantedBy = [ "boot-complete.target" ]; unitConfig.FailureAction =
  "reboot"; }` — a headless machine whose sshd fails at boot reboots
  instead of sitting unreachable. Cheap insurance for the VMs. → batch B10.
- **`machines/utm-vm/` as a dev-VM template** (Mic92) — almost exactly our VM
  shape, worth reading whole: srvos server base + disko single-disk GPT
  (500M ESP + ext4 root, deliberately not ZFS for a throwaway guest),
  networkd DHCP matched on `matchConfig.Type = "ether"` (portable across
  VMware/UTM/VZ — no interface names; stronger than the name-glob variant
  in the fork survey's networkd item), `nix.settings.max-jobs = mkDefault
  4`, per-VM authorized keys. → batch C12 takes the networkd part.
- From `phaer/nixos-vm-on-macos` `modules/nixos/base.nix`: a different VM
  architecture (headless, ephemeral, Apple Virtualization.framework with
  the host store shared over virtiofs), but two boot/networking settings
  are hypervisor-agnostic and improve our VMware/Parallels/UTM dev VM.
  The headline features (Rosetta, virtiofs store) are bound to their
  Virtualization.framework stack and don't port to ours.
  - **systemd initrd** — `boot.initrd.systemd.enable = true`. We're on the old
    scripted initrd; the systemd one is faster and more customizable.
    Drop-in. → batch C11.
  - **systemd-networkd + mac DHCP identifier** — `networking.useNetworkd = true`
    with a `10-uplink` network matching `en* eth*` and
    `dhcpV4Config.ClientIdentifier = "mac"`. Replaces our scripted
    `networking.useDHCP`, and the mac-based DHCP identifier gives predictable VM IP
    leases — directly addressing the `vm-shared.nix` comments about Fusion's
    unpredictable `enpXsY` NIC names and flaky NAT DHCP. The stronger of the
    two. → batch C12 (with Mic92's stronger `Type = "ether"` match).

---

# 2. Quick wins — not yet specced

Adoptable without a real decision. The next speccing pass (Tier-1-batch
style: check against the repo, spec, one commit each) draws from here.

## Repo, eval, and formatting guardrails

- **`system.configurationRevision = self.rev or self.dirtyRev or "dirty"`**
  (ambroisie `flake/nixos.nix`) — stamps the git rev into `nixos-version
  --json` on every host. Extends the GCE image provenance labels to every
  deployed system; one line in a shared aggregate.
- **motd provenance** (drupol `modules/base/etc/motd.nix`) — `/etc/motd`
  embeds NixOS release, nixpkgs rev, and `self.rev or dirtyRev`;
  login-time provenance for the headless servers, same idea as the
  `configurationRevision` item.
- **git-hooks.nix wired into `nix flake check` and the devShell** (ambroisie
  `flake/checks.nix` + `flake/dev-shells.nix`) — cachix's git-hooks
  flake-parts module with `pre-commit.check.enable = true`: deadnix,
  nixf-diagnose, shellcheck run as a flake check in CI and install locally
  via `shellHook = config.pre-commit.installationScript`. It's a flake-parts
  module, so it drops into `modules/` as one file. The flake-parts-native
  version of the futtetennista pre-commit baseline (fork survey Tier 2);
  today nothing lints nix/shell here.
- **git-hooks in the shell, not the check** (mightyiam + drupol) —
  `pre-commit.check.enable = false` with hooks installed via devshell
  shellHook; CI runs the formatter directly instead of duplicating.
  (The counter-position to the previous item; pick one.)
- **Pre-commit + lint baseline** — `futtetennista` `.pre-commit-config.yaml` +
  `.github/workflows/repo-checks.yml`: trailing-whitespace, detect-private-key,
  shellcheck, `check-jsonschema`, workflow lint, enforced locally and in CI
  (excludes `secret/`). Matches the NFR pre-commit standard.
- **Whole-tree formatter** (sebastianrasor `flake.nix`) — `formatter =
  pkgs.nixfmt-tree`; plus `statix` and `nixf` as dev-shell linters
  (companions to the git-hooks item above).
- **Formatting enforcement** — pedantix (drupol; treefmt-integrated
  attr-ordering per glob, e.g. enforce a canonical key order in every
  `flake.modules.*` file), `json-sort` for committed JSON, and treefmt
  `settings.on-unmatched = "fatal"` (mightyiam) so every file is
  formatted or explicitly excluded.
- **treefmt details worth copying** (Mic92 devshell/): `shfmt.includes =
  ["*.envrc" "*.bashrc"]` formats dotfile fragments, per-directory
  mypy/ruff for repo scripts, and `mkShellNoCC` for a compiler-free (much
  smaller) dev shell.
- **Eval guardrails in `nixConfig`** (mightyiam) — `abort-on-warn =
  true` and `allow-import-from-derivation = false` repo-wide. Two lines;
  complements the pure-eval tests.
- **Platform-mismatch pure-eval test** (vix `modules/ci/platforms.nix`)
  — walk every host's system + home packages and assert each package's
  `meta.platforms` includes the host's system (with a per-host skip
  list). Catches "Linux-only package added to an aggregate the Mac
  consumes" at eval time. Direct fit for `tests/`.
- **Derivation-neutrality snapshot** (mightyiam
  `modules/repository/all-check-store-paths.nix`) — a package writing a
  TOML map of every check name → out-path (`unsafeDiscardStringContext`).
  Diff it before/after a refactor to prove file moves changed no hashes.
  The exact tool for dendritic reorganizations; cheaper and more local
  than the CI closure diff. Good `make` target.
- **Per-system package filtering with `availableOn`** (sebastianrasor
  `packages/default.nix`) — `lib.filterAttrs (_: lib.meta.availableOn
  { inherit (pkgs.stdenv.hostPlatform) system; })` (plus
  `builtins.tryEval` for nested sets) so linux-only packages don't break
  `nix flake show`/CI eval on darwin and vice versa. Directly useful for
  this cross-platform flake.
- **import-tree API beyond the one-liner** (`denful/import-tree`, 269
  lines, pure builtins) — `.map lib.traceVal` (one-line "which files am
  I importing" debugger), `.leafs`/`.files` (use it as a plain file
  lister inside pure-eval tests — e.g. assert every module file has
  ABOUTME comments, or tree-shape invariants), `.filterNot` (exclude
  files per-invocation without renaming to `_`), `.initFilter`
  (redefine the discovery rule), `.addPath` (multiple roots), and tree
  roots can be flake inputs (import modules straight from another
  repo). Housekeeping: `.withLib` is a no-op since July 2026 and the
  repo moved to denful — check our pin.
- **`workarounds.nix` convention** (mightyiam) — every workaround in one
  file with upstream issue URLs, instead of hidden inside feature
  modules. Decay stays visible.
- **`.pkg.nix` convention** (mightyiam) — `import-tree.filterNot
  (hasSuffix ".pkg.nix")` lets callPackage files sit next to the
  feature module that overlays them, inside the dendritic tree.
- **direnv `watch_file` on flake parts** (ambroisie `.envrc`) — watch
  only the shell-relevant flake files so direnv doesn't reload on every
  repo edit.
- **Lock-bump commit convention** (Misterio77's AGENTS.md): manual
  flake.lock commits must summarize what actually changed upstream (compare
  the old/new revs, bullet the meaningful commits). The weekly update-lock
  PR already carries the input diff; this is the same rule for hand-run
  bumps. Worth adding to our AGENTS.md alongside the existing "call out
  lock regeneration" rule.
- **Claude Code hygiene** (srid, dustinlyons): add `permissions.deny` rules
  for `rg`/`find`/`grep` over `/nix*` to the tracked
  `users/mich/claude/settings.json` — stops agents from crawling the store
  and wedging sessions. Optional: the `sadjow/claude-code-nix` flake
  (overlay + its own cache, daily bumps) as an alternative to our
  unstable-overlay claude-code if nixpkgs-unstable ever lags.
- **claude-code hygiene, Mic92's version** (pkgs/claude-code,
  home/.claude/): wrapper exports `SHELL=${pkgs.bashInteractive}/bin/bash`
  (claude picks up broken login shells otherwise); a Notification hook
  rings the terminal bell when permission is needed — pairs with tmux
  bell monitoring.
- **Auto-load overlays** — `jseppanen` / `lucamaraschi` `lib/overlays.nix`. Reads
  `overlays/` and auto-imports every `*.nix` / subdir-with-`default.nix`, so new
  overlays never need hand-listing. Confirmed not present upstream.

## Nix daemon, GC, and build plumbing

- **Graceful-degrade substituter settings** (sebastianrasor `nix.nix`):
  `connect-timeout = 5` + `fallback = true` so an unreachable binary cache
  degrades to building instead of hanging. Worth adding for cachix
  regardless of any self-hosted cache.
- **Daemon disk headroom** (sebastianrasor `nixos-modules/nix.nix`) —
  `min-free`/`max-free` in nix.settings so the daemon auto-GCs during
  builds; `log-lines = 25` for more context on failures; `build-dir`
  moved off `/tmp` (avoids tmpfs exhaustion on big builds). Also
  `nixPath = lib.mapAttrsToList (k: v: "''${k}=''${v.to.path}")
  config.nix.registry` — derive nixPath from the pinned registry instead
  of maintaining both.
- **"Reasonable defaults" block** (drupol `modules/base/nix.nix`,
  credited to jackson.dev) — `log-lines = 50`, `tarball-ttl = 86400`,
  plus the connect-timeout/fallback and min-free/max-free pairs already
  harvested from sebastianrasor; third repo converging on the same set.
- **`nix.settings.keep-outputs = true`** (mightyiam) — GC keeps
  build-time deps of rooted outputs, so direnv dev shells survive
  `nix-collect-garbage`.
- **GC timer jitter** (ambroisie nix module) — `nix.gc` with
  `randomizedDelaySec = "10min"` and `persistent = true`; persistent
  matters for VMs suspended when the timer would have fired.
- `nix.settings`: `http-connections = 128`, `max-substitution-jobs =
  128` (parallel substitution on fat pipes) — every setting carries a
  WHY comment, a documentation style worth imitating. (GaetanLepage)
- Substituters as a data list with explicit `?priority=N` params, keys
  via `builtins.catAttrs`. (GaetanLepage)
- **Rebuild ergonomics one-liners** (EmergentMind): `git add
  --intent-to-add .` before every build (kills the "path does not exist"
  flake gotcha for new files — belongs in `make switch`/`make test`);
  `nix flake update --timeout 5` so one dead input host doesn't hang the
  bump. Plus srid's activation-hang insurance to file away:
  `systemd.services.NetworkManager-wait-online.enable = false` and
  dbus-broker `restartIfChanged = mkForce false` are the two canonical
  "switch hangs" fixes for GUI VMs.
- **Self-registry alias** (traxys) — `nix.registry."my".flake = <this
  flake>` makes `nix run my#...` and `nix flake init -t my#<template>`
  work from any directory without a path. One line next to the existing
  `registry.nixpkgs` pin in `modules/nix-settings.nix`.
- **`pkgs.master`/`pkgs.unstable` overlay inheriting `final.config`**
  (drupol) — extra-channel attrs that propagate allowUnfree etc.,
  without a second `import nixpkgs` at call sites; compare our
  overlays.nix plumbing.
- **`pkgs.inputs.<flake>.<pkg>` overlay** (Misterio77): one overlay mapping
  every flake input to `pkgs.inputs.${name}` (its packages for the right
  system). Dendritic modules then use input packages without threading
  `inputs` through specialArgs or hand-picking `system`. Would simplify our
  unstable-overlay plumbing too (`pkgs.inputs.nixpkgs-unstable.gh`).
- **Generated flake-compat shim** (drupol `modules/files/flake-compat
  .nix`) — committed shim reading `flake.lock` for the pinned narHash,
  giving `nix-build`/`nix repl` entry with zero unpinned fetches, and
  generated so it can't drift.
- **nix-index-database comma** (mightyiam + vic independently) —
  `programs.nix-index-database.comma.enable = true`: prebuilt weekly
  index, `,cmd` runs any uninstalled command, no local indexing.
- **Search the pinned inputs** (vic) — `nix search --inputs-from <repo>
  nixpkgs <term>` searches the locked nixpkgs, not the registry one;
  companion `rg-nixpkgs` greps a stable symlink to the input source.
- **Small nix tools** — `nix-melt` (flake.lock TUI), `nurl` (generate
  fetcher calls from a URL), `nix-fast-build`; one-liner `system`
  command = `nix-instantiate --eval --expr builtins.currentSystem
  --raw` (handy on a mixed-arch fleet); zsh alias `nix-shell =
  "nix-shell --run zsh"`. (mightyiam)
- **flake.nix bits** (Mic92): `nixConfig.extra-substituters` in the flake
  itself (trust prompted on first build, no host config); `?shallow=1` on
  git-hosted inputs; `renovate.json` with `"nix": {"enabled": true}` +
  an auto-merge workflow — a simpler packaged alternative to the
  update-flake-lock CI noted in the traxys survey.
- **Justfile nuggets** (vic) — current system via `nix-instantiate
  --eval -E builtins.currentSystem`; a `reboot` recipe that runs the
  boot-not-switch target first (safer kernel bumps).
- **Closure diffs between git revs** (ambroisie `pkgs/diff-flake/`) — two
  transferable techniques from his ~200-line script: the
  `.?rev=$(git rev-parse @~)#output` flake-URL trick (diff two revisions
  with no worktree juggling), and building devShells via their
  `.inputDerivation` attribute so they diff too. Could become a pre-push
  "what will this change" Makefile target across all hosts; overlaps the
  CI closure diff, which covers only pushes.
- **devShells scanned from `shell.nix` files** (sebastianrasor
  `devshells.nix`) — `lib.filesystem.listFilesRecursive` + basename
  filter auto-exposes every package's `shell.nix` as a flake devShell;
  root shellHook exports `NH_FLAKE="."` so `nh os switch` works bare in
  the repo.
- **Devshell nix.conf sync** (vix `modules/flake/shell.nix`) — generate
  a `nix.conf` from one host's evaluated `nix.settings` and export
  `NIX_USER_CONF_FILES` in the devshell, so shell substituter/key
  config can't drift from host config.

## Servers and VMs

- **`virtualisation.docker/podman.autoPrune`** (ambroisie) — weekly
  `--all` prune. The helium disk crisis (orphan podman volume) as a
  one-liner of prevention.
- **fail2ban escalating bans** (ambroisie fail2ban module) —
  `bantime-increment = { enable = true; rndtime = "5m"; }` + DEFAULT jail
  `findtime`/`bantime` — jittered, escalating bans for nitrogen's exposed
  sshd.
- **`boot.shell_on_fail` kernel param** (sebastianrasor plymouth module) —
  drop to a shell when boot fails instead of hanging; cheap insurance on
  headless boxes. Companion: `console.earlySetup = true` (keymap in
  initrd, matters for emergency prompts).
- **mosh in the ssh-server module** (ambroisie) — `programs.mosh.enable`
  opens its UDP range automatically; nice over flaky links.
- **Boot-speed pair** (sebastianrasor) — `systemd.network.wait-online
  .enable = false` plus catch-all network with `linkConfig
  .RequiredForOnline = "no"` (per-host opt-back-in); companion to the
  networkd item in the Tier-1 batch (C12).
- **`boot.initrd.systemd.network.wait-online.enable = false`** (drupol)
  — the initrd half of the wait-online kill; pairs with the main-system
  one above.
- **timesyncd without double sources** (sebastianrasor) — `servers = [ ];
  fallbackServers = [ "time.google.com" ]`: NTP from DHCP when offered,
  fallback otherwise.
- **inotify watch bump for dev VMs** (dustinlyons):
  `boot.kernel.sysctl."fs.inotify.max_user_watches" = 1048576` — stops
  file-watcher exhaustion with big repos under editors/direnv in the VM.
- **systemd-oomd on the dev VM** (traxys) — his `gui/nixos.nix` enables
  `systemd.oomd` with user/root/system slices. A big `nix build` inside the
  VM OOM-freezing the guest is exactly the failure mode this catches.
  Self-contained addition to `modules/vm.nix`.
- **VM/host one-liners** (Mic92, machines/, nixosModules/):
  `pkgs.ghostty.terminfo` (terminfo output only) in the VM's
  systemPackages so ghostty-over-SSH works — the lightweight version of
  the srvos mixins-terminfo idea in the ryan4yin survey;
  `services.getty.autologinUser` on the throwaway VM;
  `services.dbus.implementation = "broker"`.
- **Slim the closure** (drupol) — `environment.defaultPackages =
  lib.mkForce [ ]` (drops nano/perl/rsync/strace);
  `documentation.*.enable = false` for headless (measurable eval win);
  `programs.command-not-found.enable = false` in NixOS *and* HM (it's
  channel-backed and permanently broken on flake systems).
- **sudo-rs** (mightyiam + drupol independently) — `security.sudo.enable
  = false; security.sudo-rs.enable = true`: memory-safe sudo, drop-in.
- User in `systemd-journal` group — full `journalctl` without sudo
  (mightyiam); journald `MaxFileSec=3day` — time-based retention beside
  the size cap (drupol).
- `kernelParams = ["quiet" "systemd.show_status=error"]` — quiet boot,
  errors still shown; `boot.tmp.useTmpfs` + `cleanOnBoot` (both repos).
- `services.kmscon.enable` with mouse — modern VT for
  headless-with-occasional-console; swap-by-partlabel with
  `randomEncryption.enable`; `pam.loginLimits` nofile 8192; ntpd-rs
  with `log-level = "warn"`; docker `enableOnBoot = false` + rootless
  `setSocketVariable` (socket-activated daemon); `programs.nano.enable
  = false` (mightyiam).
- **`system.autoUpgrade` with `operation = "boot"`** (mightyiam) —
  auto-upgrade applies on next reboot, never live-switches a headless
  box unattended.
- **`system.etc.overlay.enable` + `services.userborn.enable`**
  (Mic92 nixosModules/workstation.nix) — perl-free /etc and user
  provisioning, faster switches. Newer-NixOS feature; test on one VM
  first. (drupol also runs `userborn` + `use-xdg-base-directories` and
  `nix.channel.enable = false` with `nixPath = mapAttrsToList (n: _:
  "${n}=flake:${n}") (filterAttrs (isType "flake") inputs)` — the
  tidiest nixPath-from-inputs one-liner seen.)
- **Lazy network mounts** (sebastianrasor `unas-lazy-media.nix`) —
  `systemd.mounts` + `systemd.automounts` with
  `automountConfig.TimeoutIdleSec = "600"`: NAS shares mount on first
  access, unmount after idle, and a down NAS never hangs boot.

## Terminal: ghostty, tmux, less

- **OSC 52 + OSC 777 scripts** (ambroisie `pkgs/osc52/`, `pkgs/osc777/`) —
  two small bash scripts: clipboard-copy and desktop-notification escape
  sequences, with the tmux DCS passthrough wrapping and screen chunking
  done correctly. Clipboard to the Mac / notifications from inside
  ssh-inside-tmux, no X forwarding; ghostty supports both. Supersedes the
  oscclip package candidate (traxys survey).
- **zsh-done long-command notifications** (ambroisie
  `modules/home/zsh/default.nix`, plugin `github:ambroisie/zsh-done`) —
  notify when a long command finishes; `DONE_EXCLUDE` is one anchored
  regex built from a list (`git (?!push|pull|fetch)`, `tail -f`, editors);
  overriding `done_send_notification()` to call `osc777` routes it through
  ssh to the local terminal.
- **tmux one-liners** (ambroisie `modules/home/tmux/default.nix`) —
  `set -s set-clipboard on` + `allow-passthrough on` (required for OSC 52
  upward through tmux); `terminal-features ",<term>:hyperlinks"` / `:RGB`
  (OSC 8 links + truecolor for terminals tmux doesn't know);
  `aggressiveResize = true` (multiple ghostty windows on one session);
  `bind-key -N "description"` on every binding so `prefix ?`
  self-documents; yank with `@yank_action 'copy-pipe'` (stay in copy
  mode); `focusEvents = true`; `bind R source-file` reload binding.
- **tmux.conf modernisms, remaining bits** (Mic92 `home/.tmux.conf`):
  `update-environment 'SSH_AUTH_SOCK ...'`, splits opening in
  `#{pane_current_path}`, `escape-time 0`, `detach-on-destroy off`, and a
  tmux-thumbs regex for nix SRI hashes. Bonus: zshrc hashes `$HOST` into a
  tmux `@host_color` so remote sessions are visually distinct.
- **Auto-tmux on ssh login** (ambroisie zsh module `launchTmux` option) —
  `[ -z "$TMUX" ] && exec tmux new-session` via `lib.mkBefore` in
  initContent; `exec` so no orphan login shell.
- **lesskey readline bindings** (ambroisie `modules/home/pager/`) —
  `programs.less.config` gives `^a ^e ^w \eb \ef ^p ^n` etc. inside less's
  search/command line, `Q` quits without clearing the screen, and `LESS`
  is set explicitly in the environment (via `lib.cli.toCommandLineGNU`) so
  it overrides git's internal pager defaults; bat reuses it:
  `programs.bat.config.pager = "''${PAGER} ''${LESS}"`. Rarely configured,
  used every day.
- **`performable:` keybind prefix** (vic ghostty config) — `keybind =
  performable:ctrl+shift+c=copy_to_clipboard`: the binding only consumes
  the key when it can act (copy only with a selection), otherwise the key
  passes through to the terminal.
- **Leader-key chords** (vic ghostty config) — tmux-style prefix inside
  ghostty: `alt+,>c` new tab, `alt+,>\` split right, `alt+,>z` zoom
  split, `alt+,>1..9` goto tab.
- **Small ghostty settings** (vic) — `shell-integration-features =
  no-cursor,sudo,no-title` (the `sudo` feature keeps terminfo working
  under sudo), `window-save-state = always`, `unfocused-split-opacity`,
  `window-colorspace = "display-p3"` (relevant on neon).
- **ghostty→tmux→nvim file-link opener** (Mic92,
  `home-manager/modules/tmux-open-file.nix`): registers a trampoline as the
  MIME/UTI handler for source files on both OSes (xdg.mimeApps on Linux;
  osacompile-built .app + `duti` on macOS), so clicking a `file://` link
  ripgrep/compilers print in ghostty opens nvim in the active tmux pane.
  We run exactly this stack on both platforms; his header comment documents
  why naive wrappers fail (GUI apps inherit launchd PATH).

## ssh

- **`StreamLocalBindUnlink = "yes"` in sshd** (drupol) — server removes
  stale forwarded unix sockets, the fix for agent/gpg socket forwarding
  breaking on reconnect. Direct fit for the ssh-into-VM workflow.
- **Tailnet-scoped ssh canonicalization** (sebastianrasor
  `home-modules/ssh.nix`) — `CanonicalizeHostname yes` +
  `CanonicalDomains ts.<domain>` so bare `ssh host` resolves to the
  tailnet FQDN, and `ForwardAgent yes` is scoped to `Host *.ts.<domain>`
  only — agent forwarding for our machines, never for random hosts. Plus
  `ControlPath` under `$XDG_RUNTIME_DIR` (tmpfs, 0700, tmpfiles rule
  pre-creates it) instead of `~/.ssh`, and
  `programs.ssh.enableDefaultConfig = false` so the rendered config is
  exactly what's written. ambroisie's companion: `includes =
  [ "config.local" ]` (and the same in gitconfig) for unversioned
  per-machine entries.
- **mDNS fleet names** (mightyiam) — avahi with `nssmdns4 = true`, fleet
  knownHosts on `<host>.local` names: no DHCP-address tracking for the
  Fusion/UTM VMs.
- **sudo via forwarded ssh-agent — pam_rssh** (sebastianrasor
  `nixos-modules/pam.nix`) — `security.pam.services.sudo.rssh = true` with
  `auth_key_file` per user: sudo on a remote host authenticates against
  the forwarded agent, no password on the box at all. Best single nugget
  of the sweep for a headless fleet.
- **gpg `reset-agent` alias** (ambroisie gpg module) —
  `gpg-connect-agent updatestartuptty /bye`: the fix for pinentry landing
  on the wrong tty after a tmux reattach.
- **sshd runtime drop-ins** (mightyiam) — `extraConfig = "Include
  /etc/ssh/sshd_config.d/*"`: an escape hatch on otherwise-immutable
  NixOS sshd config.
- **Per-host ControlPersist override** (vic) — `ControlPersist = "no"`
  for github.com while `*` keeps 10m: no stale multiplexed sockets to
  high-churn hosts.
- **HM ssh-agent user service** (vic) — `services.ssh-agent.enable` on
  Linux HM; plus nix-community `vscode-server` HM service if VS
  Code/Cursor Remote-SSH into the VMs ever happens.
- **Agent-forwarding survival in tmux** — srid's HM-managed `~/.ssh/rc`
  that re-points a stable `~/.ssh/ssh_auth_sock` symlink on each connect,
  so agent forwarding inside long-lived tmux sessions survives
  reconnects — our exact Mac→SSH→tmux-in-VM workflow. Complement: Mic92's
  `fixssh` zsh function (re-export SSH_AUTH_SOCK from `tmux
  show-environment` after reattach — the classic stale-agent fix).
- **zsh micro-patterns** (Mic92 `home/.zshrc`): `ssh-ephermal`
  (`UserKnownHostsFile=/dev/null` — right for throwaway VMs), `xalias`
  (define alias only if the command exists, keeps one rc portable across
  minimal hosts).

## git / jj

- **gitconfig beyond the specced Tier-1 batch set** (ambroisie git
  module) — `merge.conflictStyle = "zdiff3"`, `rerere.enabled`,
  `rebase.autoStash`, `fetch.prune` + `fetch.pruneTags`,
  `url."git@github.com:".insteadOf = "https://github.com/"` (pasted HTTPS
  URLs go over ssh), `blame = { coloring = "repeatedLines";
  markIgnoredLines; markUnblamables; }`. Aliases: `assume`/`unassume`/
  `assumed` (update-index --assume-unchanged), `pick = "log -p -G"`,
  `push-new`, `git = "!git"`. Global ignores parsed from a plain
  `default.ignore` file via a 6-line readLines snippet so the file stays a
  normal gitignore. Packages alongside: `git-absorb`, `git-revise`, `tig`;
  `package = gitFull`.
- **gitconfig stragglers** — `pull.useForceIfIncludes = true` (drupol;
  safety companion to force-with-lease), `rebase.instructionFormat =
  "%d %s"` (decorations in the rebase todo), `push.default = "current"`,
  `tag.sort = "taggerdate"`, alias `clone-bare-with-refspec` (fixes the
  bare-clone-for-worktrees fetch refspec), `recents` alias
  (for-each-ref by committerdate) (vic).
- **`home/.gitconfig` — the densest portable gitconfig surveyed** (Mic92).
  Beyond the git tweaks in the batch and the traxys survey:
  `commit.verbose = true` (diff in the commit-msg
  editor), `help.autocorrect = 10`, `am.threeWay = true`, `[credential
  "https://github.com"] helper = !gh auth git-credential` (gh becomes the
  token source; no keychain wiring), SSH commit signing (`gpg.format =
  ssh`), a trailing `[include] path = ~/.gitconfig.local` so per-machine
  overrides win, and aliases `uncommit = reset --soft HEAD^`, `recommit =
  !git commit -eF $(git rev-parse --git-dir)/COMMIT_EDITMSG` (recover a
  failed commit message), `checkout-pr` (fetch `pull/$N/head`).
- **Conditional git identity** (traxys) — `includes = [{ condition =
  "gitdir:~/Perso/"; contents.user = {...}; }]` gives per-directory-tree
  name/email overrides. Becomes relevant the moment work and personal repos
  share a machine; zero cost to note now.
- **mergiraf** (mightyiam + drupol independently) — syntax-aware
  structural merge driver; HM wires it into git *and* jj
  (`programs.mergiraf.enable{,GitIntegration,JujutsuIntegration}`).
- **jj sign-on-push only** (sebastianrasor `home-modules/jujutsu.nix`) —
  `signing.behavior = "drop"` + `git.sign-on-push = true`: local commits
  unsigned, signatures added at push.
- **jj block** (drupol + vic; relevant to the jujutsu skill) —
  `git.private-commits = "description(glob:'wip:*') | ..."` (never
  pushed), `snapshot.auto-update-stale = true`, `ui.default-command =
  ["--ignore-working-copy" "log"]` (bare `jj` never touches the working
  copy), `tug` alias (advance nearest bookmark), revset library
  (`closest_bookmark`, `recent()`, `why_immutable(r)`), `conf.d/`
  drop-in fragments merging with HM settings, `--scope`/`--when`
  conditional config, starship jj module replacing the `git_*` modules.
  Plus the pattern of wrapping any signing TUI with `ssh-add -l ||
  ssh-add` first.
- **gh wrapper `--unset GITHUB_TOKEN`** (mightyiam) — a stray env token
  from direnv/CI can't shadow the keyring login.
- **lazygit tuning** (mightyiam + drupol) — pager cascade
  (difftastic → delta → default, cycle inside lazygit), `git.autoFetch =
  false`, custom `N` binding = `git add --intent-to-add` on the selected
  file, `overrideGpg = true` (stops hangs on signed commits).
- **Global gitignore of agent droppings** (vic) — `.claude`, `CLAUDE.md`,
  `AGENT*`, `.aider*`, `GEMINI.md` etc. globally ignored (committed
  files unaffected); mightyiam does the same for `.envrc`/`.direnv`,
  plus direnv `warn_timeout = 0`.
- **gh-dash sections as code** (drupol) — declarative PR dashboard
  filters with per-repo checkout paths and a `gh pr checkout`
  keybinding; ports to any review queue.
- **Workflow scripts** (Mic92 home/bin/, pkgs/): `git-pr` (treefmt the
  branch, auto-`git absorb` the formatting fixes into the right commits,
  push to fork, open compare URL), `merge-when-green`, `gh-cleanup`
  (rule-based GitHub notification triage via `gh api /notifications`),
  and `systemctl-macos` (launchctl shim for systemctl muscle memory).

## zsh and $HOME hygiene

- **zsh keybinding fixes** (ambroisie `extra-mappings.zsh`) — `bindkey
  '^u' backward-kill-line` (stop ^U nuking the whole line),
  `edit-command-line` widget on `^x^e`, terminfo-guarded bindings (with
  fallbacks) for Delete/Shift-Tab/Ctrl-arrows across keymaps.
- **Completion zstyles worth lifting wholesale**
  (ambroisie `completion-styles.zsh`) — `menu select`, LS_COLORS in
  completion listings, `group-name`, `squeeze-slashes`, colored `kill`
  completion from verbose `ps`, case-insensitive `matcher-list`,
  per-category `format` strings.
- **zsh options** (ambroisie `options.zsh`) — `inc_append_history_time`
  (instead of share_history), `hist_reduce_blanks`, `hist_verify`,
  `rc_quotes`, `auto_pushd pushd_minus pushd_silent`, `auto_resume`
  (bare `vim` resumes the stopped job).
- **Skip double compinit** — `programs.zsh.enableGlobalCompInit = false`
  when home-manager runs its own; measurable startup win. (ambroisie)
- `bindkey '^[^M' autosuggest-execute` — Alt-Enter accepts and runs the
  autosuggestion in one keystroke. (mightyiam)
- `history.ignorePatterns = ["rm *"]` — destructive commands never enter
  history. (mightyiam)
- `matcher-list 'm:{a-z}={A-Za-z}'` at `lib.mkOrder 550` (before
  compinit); all six syntax-highlighting highlighters (`main brackets
  pattern regexp cursor line`); `edit-command-line` on `^e` in vicmd;
  `programs.carapace` for cross-shell completions. (mightyiam)
- **XDG tidy-`$HOME` block** (ambroisie `modules/home/xdg/`) — `HISTFILE`,
  `PSQL_HISTORY`, `PYTHON_HISTORY`, `PYTHONPYCACHEPREFIX`, `CARGO_HOME`,
  `DOCKER_CONFIG`, `INPUTRC`, `_JAVA_OPTIONS` prefs root all into XDG
  dirs; `home.preferXdgDirectories = true`; wget's hsts file via a 2-line
  `WGETRC`. Overlaps xdg-ninja (traxys survey) — this is the config to
  write once that audit runs.
- **man pages that work** — `documentation.man.cache.enable = true` (so
  `apropos`/`man -k` function) + `man-pages` and `man-pages-posix`
  packages; HM side `programs.man.generateCaches = true`. (ambroisie)
- **Misc one-liners** — `programs.jq.colors` (readable jq output); gdb:
  `add-auto-load-safe-path /nix/store` + history into XDG state;
  `home.sessionVariables.GITHUB_TOKEN = ''$(cat <secret path>)''`
  (command substitution loads an agenix secret at login, never enters the
  store); `mkDisableOption = d: (mkEnableOption d) // { default = true; }`
  (`lib/options.nix`); their comma variant with `COMMA_PICKER`
  (fzf-tmux popup) and `COMMA_NIXPKGS_FLAKE` override points; the passage
  module's config-as-wrapper micro-pattern (sebastianrasor —
  `makeBinaryWrapper` baking env-var config into the binary). (ambroisie)
- **HM collision handling** (mightyiam) — `home-manager.backupCommand =
  trash-put`: file collisions go to trash instead of aborting the
  switch. Same file: `sharedModules` sets `home.stateVersion =
  osConfig.system.stateVersion` — never drifts.
- **HM generation expiry** (drupol) — `services.home-manager.autoExpire
  { frequency = "weekly"; store.cleanup = true; }` — the HM analogue of
  `nh clean`.
- **`systemd.user.startServices = "sd-switch"`** (ambroisie) — user
  services restart on HM switch by diffing units. (drupol also sets it —
  rycee-recommended.)
- **Custom direnv stdlib helpers** (ambroisie `modules/home/direnv/lib/`)
  — extra `use …` functions (nix_shell, postgres, python) shipped via
  home-manager next to the existing offline-aware stdlib.
- `use_nix_installables() { direnv_load nix shell "$@" -c $direnv dump; }`
  — ad-hoc per-project toolsets without writing a devshell. (vic)

## macOS / darwin

- **macOS/darwin one-liners** (vic) — `ApplePressAndHoldEnabled = false` +
  `system.keyboard.remapCapsLockToControl` (no Karabiner); darwin
  tooling installed from the pinned nix-darwin input; `nix.gc` wrapped
  in `optionalAttrs config.nix.enable` so modules eval on
  Determinate-managed Macs.
- **keyd mac-modifier layout for Linux** (vic `macos-keys.nix`) —
  left-Alt as ⌘ with Cmd-C/V/T/W translated: Mac muscle memory inside
  the Fusion/UTM VMs.
- **mac-app-util** (dustinlyons, wimpysworld): trampolines so
  nix/HM-installed `.app` bundles appear in Spotlight and survive
  store-path changes in the Dock — fixes a real papercut with our
  nix-installed GUI apps (Zed). (Split out of the nix-homebrew decision
  item below — this half is uncontentious.)
- **`SSH_SK_PROVIDER` via `environment.variables` in a darwin module**
  (arianvp) — same as the exports now in users/mich/zshenv + bash_env,
  but system-wide (`/usr/lib/ssh-keychain.dylib`), covering non-login
  contexts too. Optional consolidation; the dotfile exports work today.
- **Declarative Mac App Store** (Mic92 darwinModules/app-store/):
  `pkgs.mas` + a ~40-line activation script diffing `mas list` against a
  wanted-ID list, installing missing and uninstalling unwanted.
  Complements our masApps if drift bothers us.
- **On-demand debug shell on any CI arch** (Mic92
  .github/workflows/os-ondemand.yaml): a 20-line `workflow_dispatch`
  workflow whose one step is `mxschmitt/action-tmate` with an OS-choice
  input — an interactive shell on a macos/arm64/x86 runner when CI-only
  failures need poking. Port as-is.

## CI micro-patterns

- **Bump PRs that trigger required checks** — vic's scheduled job pushes
  with a PAT (`secrets.PAT` as `GH_TOKEN`) and embeds the update output
  in the commit body; the exact fix for our ci-dispatch-pr-gotcha.
- **Auto-merged lock bumps with a bot PAT** (GaetanLepage) — `peter-evans/
  create-pull-request` with `secrets.BOT_GITHUB_TOKEN` (PR triggers
  required checks) then `gh pr merge --rebase --auto`. Together with
  vic's PAT-pushing bump job, two working implementations of the
  ci-dispatch-pr-gotcha fix.
- **gh-flake-update's pre/post build distinction** (drupol
  `pkgs/by-name/gh-flake-update/`) — build selected toplevels *before*
  `nix flake update` so "already broken" and "update broke it" are
  distinguished in the PR body (collapsible per-host dix diffs +
  captured failure logs). Refinement for our update-lock workflow. Uses
  the `nothing-but-nix` action to reclaim runner disk.
- **Dynamic matrix from nix eval** (vic) — `nix-instantiate --json --eval`
  of a hosts-by-system helper → `fromJSON` into the job matrix; each build
  job appends its result store path to `$GITHUB_STEP_SUMMARY`.
- **`/check` comment-triggered CI** (vic) — expensive multi-OS `nix flake
  check` runs only when a PR comment says `/check`.
- **upterm scratch runners** (vic) — workflow_dispatch jobs turn GH
  runners (ubuntu, arm, macos) into throwaway ssh boxes; the runners
  exist as fleet hosts with stub roots so their configs eval. Free
  aarch64/macos scratch machines.
- **Stub-root eval trick** (vic) — `fileSystems."/".device = "/dev/null";
  fsType = "auto"; boot.loader.grub.enable = false` lets hosts without
  real hardware (WSL!) eval and build in CI.
- **Dependabot for the GitHub Actions themselves** (dustinlyons): a small
  `.github/dependabot.yml` keeps the pinned `actions/checkout@v5` /
  `cachix/install-nix-action@v31` versions current via PRs instead of
  silently aging. (Leftover from the adopted build-every-closure item.)
- **CI notifier packaged in the flake** (ambroisie `.woodpecker/` +
  `pkgs/matrix-notifier`) — the notify step is just `nix run
  '.#matrix-notifier'` on success and failure; the pattern (CI tooling as
  a flake package) ports to GitHub Actions.
- **flake-inputs cache-priming derivation** (Mic92): three-line
  `runCommand` interpolating every input's store path, built in CI so all
  input sources land in the binary cache — later checks/rebuilds never
  re-fetch. Adopt together with the already-noted cachix CI item.
- **build-status join-job trick** (traxys) — one required status check
  standing in for a whole matrix. Worth keeping regardless of the CI
  cachix decision.
- **ssh exit-255 mapping** (sebastianrasor `hercules-ci.nix`) — after an
  ssh deploy, `|| exit "''${?/255/0}"`: host-unreachable (a powered-off
  machine) passes, real switch failures still fail.

## GCE roadmap (self-originated)

- **Launch-verify gVNIC**: after the next `gce/upload`, boot an instance
  with `--network-interface nic-type=GVNIC` and confirm the NIC is eth0
  with the gve driver bound and a DHCP lease.

---

# 3. Blocked on the secrets decision

The standing "no secrets management" decision is the biggest single
unblock in this file: backup credentials, tailscale auto-join,
vaultwarden, and several quality-of-life items all queue behind it.

## The options (pick one, or a combination)

- Misterio77: `sops.age.sshKeyPaths = map (k: k.path) (filter (k: k.type
  == "ed25519") config.services.openssh.hostKeys)` — the host's existing
  SSH key *is* the age identity; zero extra key material to provision on
  new VMs (darwin caveat: hardcode the path, no `services.openssh` there).
- dustinlyons: ciphertexts in a separate private repo pulled as a
  `flake = false` input — public config repo stays secret-free; plus
  scripted USB-stick key bootstrap for day 0.
- EmergentMind: GitHub access token into nix.conf via `nix.extraOptions =
  "!include ${config.sops.secrets."tokens/...".path}"` with a
  `config ? "sops"` guard — kills rate limits without the token in the
  store.
- wimpysworld: nixos-anywhere `--extra-files` stages host SSH keys +
  age keys at provision time, so identities are stable from first boot.
- **TPM-sealed age keys for sops-nix** (sebastianrasor
  `nixos-modules/secrets/default.nix`) — `age-plugin-tpm`: each host's
  age identity is an `AGE-PLUGIN-TPM-…` recipient committed in the repo
  (only that host's TPM can decrypt), installed by an activation script,
  with `sshKeyPaths` + `generateKey` fallback for hosts without a listed
  key. GCE instances have vTPMs; the ssh fallback covers the VMs. Kills
  key-distribution ceremony entirely.
- **agenix with directory-derived naming** (ambroisie
  `modules/nixos/secrets/default.nix`) — `.age` files live next to the
  host, a small mapper auto-registers the directory into `age.secrets`
  (filename = secret name), guarding `owner` on whether the user exists
  in the config. Dendritic-friendly shape if the agenix route wins.
- **agenix as the lighter secrets option** (ryan4yin) — age keys =
  existing ssh keys, one `secrets.nix` mapping files to recipients.
  Fewer moving parts than sops-nix, more structure than git-crypt.
- **agenix-rekey** (GaetanLepage) — master identity in-repo, per-host
  rekeyed secret stores, `age.rekey.hostPubkey` inline in each host
  entry: encrypt once to a master key, machine-rekeys per host. A
  distinct workflow option for the standing secrets decision. Related:
  HM-inside-NixOS gets its own agenix identity (itself an agenix secret
  owned by the user) — clean root/user secret separation.
- **Secret management options from the fork survey** — pick one:
  - `cdenneen` — sops-nix wired as a home-manager module (`.sops.yaml`, age +
    `creation_rules` path_regex, `inputs.sops-nix.homeManagerModules.sops` through
    `mksystem`). The most complete, directly adoptable integration.
  - `sandangel` — git-crypt (`.gitattributes`: `secret/** filter=git-crypt`).
    Lightweight; less powerful than sops. (Removed at their HEAD, intact in history.)
  - `smallstepman` — sops-nix + `sopsidy` sourcing each secret from Bitwarden/`rbw`
    with a systemd oneshot to materialize rbw config at boot. Advanced.
  - `futtetennista` — `@@key@@` placeholder templating substituted from a
    JSON-Schema-validated `secret/config.json` (`replace_secrets.sh`). A
    no-extra-tooling option if sops feels heavy.
- **Runtime secrets via Bitwarden passwordCommand** (traxys) — his
  `personal-cli/hm.nix` wraps `bw get item <uuid> | jq` in `bwPass`/`bwUser`
  writeShellScripts and feeds them to any HM option taking a
  `passwordCommand` (he drives CalDAV auth this way). We already install
  bitwarden-cli and have an open "no secrets management" decision — this
  is another option: no new tool, nothing on disk, secrets pulled at use
  time. Limits: needs an unlocked bw session, only covers tools with
  command hooks.
- **Private outer flake for sensitive config** (shazow
  `templates/nixos-device` + `mkSystemConfigurations`): the public repo
  exposes a constructor; a private outer flake instantiates it with the
  sensitive bits (hashed password, disk/FDE layout). A no-crypto option
  for the standing secrets decision — directly addresses the committed
  `hashedPassword` wart. Cost: a second repo and template drift; closest
  cousin is dustinlyons' private-repo-as-input.
- GCP Secret Manager (roadmap tailscale item) — cloud-side option for
  GCE instances specifically.
- **Recovery recipients** (sebastianrasor `.sops.yaml`) — YubiKey age
  recipients listed alongside per-host keys, so secrets stay editable
  if all hosts die; worth copying into any future sops setup.

## Unblocked once decided

- **Tailscale auto-join on first boot** (highest-leverage for fleet deploy;
  needs the secrets decision first). `base` enables tailscaled but it's inert
  until `tailscale up`. A small boot service that pulls an auth key from GCP
  Secret Manager (or instance metadata) and runs `tailscale up` makes every
  instance self-join the tailnet — the turnkey "deploy many places" property.
  Depends on picking a secrets story (agenix/sops or GCP Secret Manager).
  Extension (decided 2026-08-25, fleet role split): exit nodes are the same
  mechanism plus a tag — tagged auth key, `--advertise-exit-node`, and
  tailnet-policy `autoApprovers.exitNode = ["tag:exit"]` so a fresh node is
  exit-approved with no console interaction. Exit nodes are stateless cattle
  (fresh identity per deploy, nothing backed up); control plane stays
  hosted Tailscale, no headscale. Hygiene cost: stale node records after
  redeploys — ephemeral keys or occasional cleanup.
- The vaultwarden/identity-stack project (section 4) — admin token at
  minimum.
- The backup project (section 4) — repository credentials.
- **Secret host inventory** (vic) — `programs.ssh.includes` pulls a
  sops-encrypted ssh config fragment, so private hostnames/IPs never
  appear in the repo; companion activation step symlinks sops-decrypted
  keys into `~/.ssh` (keys never in the store).
- **LLM API keys via sops template + $HOME .envrc** (vic) — sops renders
  `export ANTHROPIC_API_KEY=...` to a file, a direnv lib function
  sources it, and `~/.envrc` is one line — keys decrypted at
  activation, never committed, never in the store.
- **sops rotation** (vic) — rotation is one xargs line; a monthly cron
  workflow files a GitHub issue as a rotation reminder (CI can't rotate
  what it can't decrypt). The nag pattern generalizes to cert renewal.
- Not blocked, related: **`gh auth token` → nix.conf at activation**
  (Mic92 `home-manager/coder.nix` 163–170): an HM activation step writes
  `access-tokens = github.com=$(gh auth token)` into
  `~/.config/nix/secrets.conf`; nix.conf carries `!include secrets.conf`
  (soft include — skipped if absent). Same goal as EmergentMind's sops
  variant but with zero secrets infrastructure — gh is already
  authenticated here.

---

# 4. Projects and real decisions

## Backup and DR — first priority (2026-08-25 fleet discussion)

Per the fleet role split: helium is the fleet's only stateful machine
and the only backup target; offsite copy (house = total-loss failure
domain) is the one DR item that can't be solved by redeploying.

- **Backup baseline path list** (ambroisie
  `modules/nixos/services/backup/default.nix`) — whatever backup tool is
  chosen, the unconditional baseline is the keeper: `/etc/machine-id`,
  `/var/lib/nixos` (UID/GID map), and the ssh host key paths derived from
  `config.services.openssh.hostKeys` rather than hardcoded. His restic
  module also shows services registering their dump dirs into the backup
  module's `paths` (postgres-backup example). The servers currently have no
  declarative backup story.
- **Backups follow the service** (sebastianrasor postgresql-backup) — the
  backup module's enable defaults to `config.<ns>.postgresql.enable`, so
  enabling the service enables its backup; detail for the backup-baseline
  item above.
- Restic timers as `OnActiveSec`/`OnUnitActiveSec = "6h"` (relative
  cadence, not calendar); forgejo `dump.enable = false` + restic on
  `repositoryRoot`/`lfs.contentDir` directly (zip dumps are
  backup-unfriendly). (ambroisie — from the small service one-liners)
- rsync.net borg: `BORG_REMOTE_PATH = "borg14"` (required since
  2025-05) — sharp edge to remember if borg-to-rsync.net becomes the
  helium offsite target. (GaetanLepage)
- **ZFS replication via `services.zfs.autoReplication`** (GaetanLepage)
  — one option block + knownHosts pin; simpler than syncoid. Relevant to
  the helium backup story only if ZFS ever enters the picture.
- **Boot-generation pinning** (EmergentMind): `just pin` copies the current
  systemd-boot entry to `hosts/<n>/pinned-boot-entry.conf` (title
  "PINNED:"), registers a GC root for that generation, and the module
  re-injects it via `boot.loader.systemd-boot.extraEntries` guarded by
  `lib.pathExists`. A known-good generation that survives both GC and
  `configurationLimit` — nice safety rail for the VMs, portable to a `make
  pin` target.

## Fleet structure (dendritic peers; structural)

- **Typed host registry as flake-parts options — the centerpiece**
  (GaetanLepage `modules/flake/hosts/{nixos.nix,home.nix,_utils/base.nix}`).
  Hosts declared as `nixosHosts.<name>` / `homeHosts.<name>` submodules
  with `system`, `unstable` (bool picking which nixpkgs input evaluates
  the host), `tags`, `primaryUser`, `modules`, `homeManagerModules`,
  `specialArgs`, and a `finalPackage` output field. From this one
  registry he derives `nixosConfigurations`, `homeConfigurations`, the
  colmena hive (per-host nixpkgs/specialArgs survive into it), deploy-rs
  nodes, and per-system build checks. The strongest structural idea of
  the whole survey series: the fleet axes (baseline/substrate/role/
  exposure/identity) could become typed submodule options on exactly
  such a registry, with knownHosts/DNS/deploy targets all reading from
  it. Better than ad-hoc `nixosSystem` call sites. Registry option
  types worth noting: `types.pathInStore` for a nixpkgs input,
  `types.pkgs`.
- **Hosts as first-class option values** (mightyiam `modules/nixos.nix`)
  — `nixos.configurations` as a `lazyAttrsOf submodule`;
  `flake.nixosConfigurations` and per-system checks are derived from
  it, and any feature module can extend the host schema (facter report
  path, hostname defaulted from attr name) or iterate all hosts. The
  flake-parts `systems` list is computed from the hosts' actual arches.
  Judgment call whether to adopt the layer; the "iterate hosts from a
  feature module" capability is the part worth having.
- **Single fleet inventory file** (vix `modules/hosts.nix`) — every
  host/home declared in one attrset table, each host's composition in
  its own ~20-line file. A one-file fleet table maps directly onto the
  fleet-axes model, den not required.
- **Three-tier namespace discipline** (GaetanLepage; his answer to name
  soup). Tier 1: one file = one named aspect (`nixos.nh`). Tier 2:
  explicit aggregator files — `modules/nixos/core/imports.nix` is
  literally `flake.modules.nixos.core.imports = with
  config.flake.modules.nixos; [ agenix bootloader nh ... ]`; membership
  readable in one place instead of scattered self-registration
  (wash-to-better vs ours: traceability for one extra list). Tier 3: big
  config trees (neovim, shell) demoted to *plain* modules under
  `_`-prefixed dirs, pulled in with one `imports = [ ./_dev ]` line —
  keeps the aspect namespace small on purpose (better; worth adopting).
  He's inconsistent about it in places — pick one style.
- **Host-local modules and secrets colocated** (GaetanLepage) — every
  host dir has its registry entry plus `_nixos/` full of plain modules,
  `.age` secrets sitting next to the module that declares them. Per-host
  exceptions never touch shared aspects. Clean convention, worth copying
  wholesale.
- **Standalone-HM hosts as first-class fleet members** (GaetanLepage) —
  machines without root (nix-community builders, a colleague's cluster,
  his Mac) live in `homeHosts` with the same core aggregate and secrets
  machinery; checks build `activationPackage`; home prefix computed
  from `hostPlatform` with a `throw` fallback. The missing fourth class
  next to nixos/darwin/home-in-nixos — relevant for managed presence on
  corporate boxes.
- **`primaryUser` as a registry-driven specialArg** (GaetanLepage) —
  every shared module takes `{ primaryUser, ... }` instead of hardcoding
  the user; also `configName` and `nhSwitchCommand` specialArgs so the
  HM nh module aliases the right switch command per config type.
  Directly addresses our known follow-up (hardcoded user in gui/fusion
  modules).
- **Cross-class sharing via hoisted options** (mightyiam) — shared
  values live in one top-level option (`options.nix.settings` at the
  flake-parts level), and the nixos and home-manager modules each
  `inherit` from it. The dendritic answer to nixos/darwin/HM
  duplication.
- **Typed aggregates with static implication** (mightyiam
  `modules/lib.nix` `mkModuleOption`) — aggregates as
  `deferredModuleWith` options where `pc` statically includes `base`,
  so hosts import one name; `key` makes modules dedupe across import
  paths. His pattern doc calls bare `flake.modules` an anti-pattern
  ("not declaring options"); counterpoint: our explicit aggregates are
  simpler and the same implication is one `imports` line inside the
  aggregate. Optional ~30-line upgrade if aggregate layering gets
  repetitive.
- **flake-aspects** — small dependency-free transpose: write
  `flake.aspects.<name>.{nixos,darwin,homeManager}` so one feature file
  holds all classes under one key instead of three `flake.modules.*`
  attrpaths. The low-risk middle ground if class-first grouping ever
  chafes.
- **Parameterized feature modules** (drupol `modules/facter/facter.nix`)
  — a feature as a function taking per-host arguments
  (`flake.modules.nixos.facter = path: {...}`, consumed as `(facter
  ./facter.json)`). Kills per-host boilerplate that varies only in data
  (disk IDs, image params).
- **Identity metadata as single source** (drupol user aspect `meta` =
  email/fullname/key/authorizedKeys; mightyiam's `users` submodule
  generating per-user aggregates) — one attrset feeding git signing,
  authorized_keys, etc. Relevant to the fleet-axes identity axis; worth
  it the day identity facts are duplicated across modules.
- **Features own their meta-files** (mightyiam
  `modules/repository/files.nix`, github:mightyiam/files) — `.gitignore`
  generated from an aggregated `git.ignore` option (the VM module
  declares `*.qcow2` where VMs are configured); README assembled from
  per-module text fragments. The aggregated-gitignore option is the
  most portable piece.
- **`ifTheyExist` group filter** (Misterio77 Foundry
  `hosts/common/users/gabriel`): `extraGroups = ifTheyExist [ ... ]` with
  `ifTheyExist = groups: builtins.filter (g: builtins.hasAttr g
  config.users.groups) groups` — one user definition lists every group it
  might want, and hosts that don't define a group just skip it. Fits
  `users/mich/nixos.nix` serving servers and workstations from a single
  file. (ambroisie's `groupsIfExist` is the same idea.)
- **Option aliasing into HM** (ambroisie `modules/nixos/home/`) —
  `lib.mkAliasOptionModule [ "my" "home" ] [ "home-manager" "users"
  <name> ... ]` kills the `home-manager.users.x` boilerplate at system
  level; a technique independent of their structure.
- **flake-file: inputs colocated with features** (all three dendritic
  surveys independently; `denful/flake-file`) — fixes the dendritic
  pattern's one real asymmetry: features are per-file but `flake.nix`
  inputs are centralized. Each module declares the inputs it consumes
  (`flake-file.inputs.<name>.url = ...`) next to the feature; `nix run
  .#write-flake` regenerates a do-not-edit `flake.nix`, and a check
  fails CI when it's stale. Deleting a feature file deletes its input.
  Cost: `flake.nix` becomes a generated artifact. Fits this repo with
  no other changes; the biggest drift-killer on offer.
- **Mostly-non-flake inputs** (mightyiam) — nearly all inputs `flake =
  false`, importing `${input}/flake-module.nix` by path; tiny lock
  file, no `follows` plumbing. Works while upstream layouts are stable;
  mild fragility. A real alternative to follows-chasing.
- **Generated fleet diagrams** (vix `modules/diagrams.nix`) — mermaid
  diagrams rendered from the config graph into the repo; machinery is
  den-specific but the idea ports.
- **DNS zone as a flake output** (GaetanLepage `modules/flake/dns/`,
  dnscontrol-nix) — records built with nix lib functions, creds via
  agenix, OVH registrar. His TODO ("move this to host definitions")
  converges on deriving DNS from the host registry — the concrete tool
  if we ever want declarative DNS.
- **Test harness host access** (vix `modules/ci/test-base.nix`) —
  `_module.args.ci` exposes every host's evaluated `config` to test
  modules by hostname; cleaner than each test re-deriving
  `nixosConfigurations.<x>.config`.
- **checkmate** (denful) — a separate checker flake that tests a target
  flake via `--override-input target .`, keeping dev/test deps out of
  the config's own inputs. Niche but tidy.
- **Checks aggregate beyond host toplevels** (Mic92
  checks/flake-module.nix): besides the per-host toplevels, he folds all
  `self'.packages` (with a blacklist for huge artifacts), per-package
  `passthru.tests`, all `devShells`, and home-manager activation scripts
  into `checks`, so one `nix flake check` covers everything. The
  HM-activation-script-as-check piece is the missing HM coverage in our
  eval tests.
- **nixos-facter over hardware-configuration.nix** (drupol, mightyiam
  both) — committed JSON hardware report; `detected.dhcp.enable =
  false` keeps it from fighting explicit network config. More useful if
  bare metal ever joins the fleet.

## Fleet trust: SSH keys and CAs

- **Fleet-wide knownHosts from host pubkey options** (mightyiam
  `modules/ssh.nix`) — declare each host's ssh host pubkey as an option
  in its host file; a base module iterates all host configs and folds
  every key into every host's `programs.ssh.knownHosts`.
  Zero-maintenance mutual trust across the fleet, darwin included as a
  consumer. Portable directly by iterating
  `config.flake.nixosConfigurations`. Supersedes the Misterio77
  committed-pubkeys item (six-config survey) with less ceremony.
- **Fleet SSH config derived from the flake itself** (Misterio77;
  EmergentMind variant). Commit each host's `ssh_host_ed25519_key.pub` next
  to its host file; one module generates `programs.ssh.knownHosts` for
  every configuration name (kills TOFU prompts and known_hosts drift across
  Mac↔VMs↔WSL), and an HM module generates the client matchBlocks the same
  way — add a host, get its SSH entry and trust anchor for free. The
  committed pubkeys later double as sops-nix/ssh-to-age recipients if that
  secrets route is chosen.
- **SSH host-certificate CA instead of per-host knownHosts**
  (Mic92 darwinModules/openssh.nix): `programs.ssh.knownHosts.<name> = {
  certAuthority = true; hostNames = [...]; publicKeyFile = ./ssh-ca.pub; }`
  works identically on nix-darwin and NixOS; host keys signed once
  (`ssh-keygen -s`, domain principals to avoid "not a listed principal"
  warnings). The alternative to Misterio77's committed-pubkeys approach
  that survives VM rebuilds without re-committing keys — one CA file,
  rebuilt VMs just get re-signed.
- **SSH CA on hardware-backed keys** (arianvp) — the logical next step
  after the Secure Enclave key setup on neon. arianvp keeps two FIDO2
  tokens, each holding a login key *and* a CA key; each CA cross-signs the
  other token's login key, so losing one token doesn't lock him out.
  Servers trust the concatenated CA pubkeys (`TrustedUserCAKeys`) plus a
  revocation list (KRL) in git — no per-machine authorized_keys sprawl. A
  new machine means signing one cert, zero server-side changes. Our
  version: the NixOS hosts (helium, nitrogen, VMs) trust a CA, and each
  Mac's enclave key gets a cert. His ~20-line `authorizedPrincipals`
  module (`modules/ssh-authorized-principals.nix`) is liftable as-is.
  Complementary: Mic92's *host* CA covers the other direction of trust.
- **`ssh-keygen -K` recovery one-liner** (sebastianrasor fish.nix) —
  re-download FIDO resident ssh keys from a YubiKey onto a fresh
  machine. Plus the same file's **guarded exec-into-preferred-shell**:
  from bash, exec the preferred shell only when the parent isn't already
  it, `BASH_EXECUTION_STRING` is empty, and `SHLVL == 1`, preserving
  `--login`; portable to a zsh bridge.

## Deploy and provisioning

- **Idempotent push deploy via prebuilt closure** (sebastianrasor
  `hercules-ci.nix`) — build `config.system.build.toplevel` locally or in
  CI, then over ssh: compare `readlink -f /run/current-system` against the
  toplevel path and exit early, else `nixos-rebuild --no-reexec switch
  --store-path ${toplevel}`. Zero eval on the target, free redeploys.
  Slots into the Makefile remote targets for helium/nitrogen; the
  lightweight cousin of `nixos-rebuild --target-host` (ryan4yin survey) and
  the pull-deploy items (Foundry, Mic92 pre-warm).
- **`nixos-rebuild --target-host` instead of rsync + remote rebuild**
  (ryan4yin) — the lightweight version of colmena-style push deploy:
  `nixos-rebuild switch --flake .#vm-aarch64-fusion --target-host
  mich@$NIXADDR --use-remote-sudo` builds on the Mac (we already have
  `nix.linux-builder`) and pushes the closure over SSH. No `/nix-config`
  rsync, no flake eval inside the VM, VM never needs the repo. Decision:
  where builds should happen (Mac builder VM vs guest).
- **nixos-anywhere + disko provisioning** (sebastianrasor
  `nixos-configurations/sunflower/`) — one-command install over ssh with
  the partition layout declared as a disko module; `--extra-files` stages
  keys, `--copy-host-keys` preserves host identity, and his README
  documents the second-rebuild wart when secrets key off new host keys.
  Directly aimed at the TransIP provisioning pain (sticky installer boot,
  rescue-mode traps). Joins the existing disko threads: Mic92's rescue
  recipes and wimpysworld's `--extra-files` bullet (six-config survey).
- **Debian-to-NixOS install script** (ambroisie
  `hosts/nixos/porthos/install.sh`) — on a Debian rescue system:
  Determinate installer, `nix profile install nixpkgs#nixos-install-tools`,
  `nixos-generate-config --root /mnt`, `nixos-install --flake`. The
  TransIP/helium situation as a script; complements the nixos-anywhere
  item above.
- **Rescue recipes for Makefile targets** (Mic92 tasks.py): kexec any
  Linux VM into a NixOS installer (`nixos-images` kexec tarball), and
  `disko --mode mount` from a rescue system to remount the committed
  layout — the practical "reinstall a broken VM" story once disko lands.
- **Rescue ISO as a fleet host** (vic `hosts/bombadil.nix`) — personal
  installer ISO built like any other host: `installation-cd-base.nix` +
  persistent home on a labeled partition + `mkImageMediaOverride` to
  un-force installer defaults. Compare our installer-iso package.
- **Pull-based auto-upgrade from CI** (Misterio77 Foundry
  `modules/nixos/hydra-auto-upgrade.nix`): each host runs a timer polling
  the CI instance for the latest successful build of its own toplevel job,
  fetches the store path straight from the binary cache (no eval, no repo on
  the host), refuses downgrades by comparing flake `lastModified` timestamps
  (`IGNORE_TIMESTAMP=true` to override), prints an `nvd diff`, then
  test-activates and sets the system profile + bootloader entry. The same
  script doubles as an admin CLI (`cached-nixos-rebuild diff|test|switch|boot`).
  Our version would poll GitHub Actions + cachix instead of Hydra.
  Composes three items already listed: the adopted build-every-closure CI,
  Mic92's pre-warm-next-closure (the fetch half of the same idea), and the
  dirty-tree guard (his upgrade timer disables itself on dirty checkouts).
  Prerequisite: per-host closures pushed to cachix.
- **Pre-warm the next closure** (Mic92 nixosModules/update-prefetch.nix):
  hourly idle-priority service fetches CI's latest build for this host
  and roots it at `/run/next-system`, so the eventual switch is instant;
  offline guard via `ip r g`. Needs per-host closures in a cache first —
  pairs with the pull-deploy notes above.
- **`inputs.self ? rev` dirty-tree guard** (Misterio77): systemd timers /
  automation that should only run from a committed config get `enable =
  inputs.self ? rev` — auto-upgrade or CI-pull machinery silently disables
  itself on a dirty checkout. File next to any future auto-upgrade work.
- **Three deploy backends off one registry** (GaetanLepage) — nh
  interactive, colmena by `tags = ["server"]`, deploy-rs for checked
  pushes; tags are the grouping mechanism (maps to the role axis).
  Devshell `rebuild` runs `nh os switch --target-host root@$h
  --build-host root@$h` — build on the target, useful when the client is
  a weak or foreign-arch machine (our aarch64 Mac pushing to x86
  servers). Devshell `update` verb = flake update + deploy + commit +
  push in one command.
- **deploy-rs nodes derived from nixosConfigurations** (drupol
  `modules/flake-parts/deploy.nix`) — `deploy.nodes = lib.mapAttrs'`
  over `config.nixosConfigurations`, arch read from each config; the
  derive-per-host-tooling-from-config move applies to any deploy/CI
  matrix generation.
- **Minimal CI deploy user** (ambroisie porthos users + `pkgs/drone-rsync`)
  — dedicated user, `createHome = false`, home at the docroot, CI
  runner's pubkey; CI side loads a passphrase-protected key
  non-interactively via ephemeral `ssh-agent` + `sshpass -P passphrase`.
- **CI deploy gating** (sebastianrasor `hercules-ci.nix`) —
  `passthru.prebuilt = toplevel` so the closure is built and pushed
  before the ssh effect runs; `runIf (branch == "main")`.
- **Remote NixOS server deploy** (nrolland `servers/scw-stardust/`). Nested
  sub-flake: `make create` provisions a cheap cloud VM via cloud-init + nixos-infect,
  `make deploy` does rsync + remote `nixos-rebuild switch --flake`; minimal disko
  GPT layout; age-based `.sops.yaml`. Plus two reusable modules: `tailscale-server.nix`
  (enable tailscale + correct firewall) and a typed `sshKeys` option module. Good
  template if we ever add a remote box.
- **Per-host runbooks next to host files** (srid): `mod.just` per host —
  backup/restore/health-check sequences as versioned recipes namespaced
  `just <host> <task>`, living beside the host config. Ports to per-host
  Makefile includes; beats a wiki for "how do I poke this box" knowledge.

## Caching and builders

- **Self-hosted binary cache via harmonia** (both repos independently:
  ambroisie `modules/nixos/services/nix-cache/`, sebastianrasor
  `nixos-modules/harmonia.nix`) — serve the builder's store signed with a
  private key, ~40 lines; sebastianrasor exposes it over the tailnet as
  `cache.ts.<domain>`. A cachix complement with helium as builder+cache.
  Caveat: his nginx proxy block wrongly references `services.nix-serve`
  options — don't copy verbatim. Related cheap trick: Misterio77's
  `nix.sshServe` (below).
- **CI feeding the cachix cache** (traxys) — the cache and per-host
  substituter now exist (seeded from the Mac); the unadopted half is CI
  pushing built artifacts, bounded by the 5 GB free tier, so it needs a
  selective pushFilter (e.g. only container-server tarballs), and the
  `CACHIX_TOKEN` secret is already in place.
- **Register the Fusion VM as a real remote builder** (Mic92, srid) —
  alternative/supplement to `nix.linux-builder`: builder side gets an
  unprivileged `nix` user (`isSystemUser`, ssh key, `trusted-users`);
  client side `nix.distributedBuilds` + `buildMachines` with `protocol =
  "ssh-ng"`, `publicHostKey = base64 -w0 <hostkey.pub>` (no TOFU breakage in
  daemon context), and supportedFeatures `kvm`/`nixos-test`/`big-parallel` —
  which linux-builder can't offer the same way. Decision: one more always-on
  VM vs on-demand linux-builder; could be scripted to prefer the VM when
  it's up. Related cheap trick (Misterio77): `nix.sshServe` exposes any
  host's store over `ssh-ng://nix-ssh@host` as an ad-hoc substituter
  between our machines — no cache service needed.
- **Remote-builder roster** (GaetanLepage
  `modules/home/core/nix-remote-builders/`) — per-builder
  `maxJobs`/`speedFactor`/`supportedFeatures`; `mandatoryFeatures =
  ["cuda"]` so only CUDA jobs route to the CUDA box; self-exclusion via
  `lib.optionals (hostName != "spark")` so a host never lists itself;
  builder hostname read from `programs.ssh.settings.<alias>` so ssh
  config and buildMachines share one source. Server side: dedicated
  `nix` user + trusted-users.

## Services and self-hosting (helium)

### The private identity stack (sebastianrasor: vaultwarden + authentik + headscale)

Read in full (fourth pass, on request). ambroisie has no equivalent — he
uses hosted Bitwarden plus the already-harvested bw-pass client and
nginx-sso. sebastianrasor's stack is the complete self-hosted version and
its topology is the most transferable part.

**Topology — one private host, one tiny public host.** carbon (home
server) runs everything: authentik, vaultwarden, forgejo, immich,
paperless, radicale, buildbot, harmonia, postgres. Its reverse-proxy
instance sets `baseDomainName = "ts.<domain>"` and does *not* open the
firewall — every service gets an nginx vhost on a tailnet-only name.
nephele (small public VPS) runs headscale plus the `*-public-proxy`
modules; its reverse-proxy instance sets `baseDomainName = <domain>` with
`openFirewall = true` and forwards only the chosen few into the tailnet
(authentik for login, immich share links, the buildbot webhook path).
Same ~70-line module, instantiated twice with different base domains —
the public/private split is one option value per host.

- **Real certs for tailnet-only services**: `.ts.<domain>` names are real
  subdomains, so DNS-01 ACME issues them like any other — no self-signed
  CA inside the tailnet, and the single-cert `extraDomainNames`
  collection (already harvested) picks them up automatically.
- **Service discovery via headscale MagicDNS `extra_records`**
  (`nixos-modules/headscale.nix`): `base_domain = "ts.<domain>"` plus one
  A-record per service name pointing at the serving host's tailnet IP.
  On real Tailscale the equivalent would be split-DNS or public DNS
  records pointing at the tailnet address.
- **The OIDC bootstrap circle, solved three ways at once**: headscale
  clients must reach the IdP *before* they're on the tailnet, but
  authentik lives behind it. (a) nephele publicly proxies
  `authentik.<domain>` → `https://authentik.ts.<domain>`; (b) on carbon,
  `networking.hosts."127.0.0.1" = [ "authentik.<domain>" ]`
  short-circuits the public name locally; (c)
  `only_start_if_oidc_is_available = false` + the restart-oneshot
  (reference section) handles boot ordering.

**Vaultwarden module** (`nixos-modules/vaultwarden.nix`, 52 lines) —
directly liftable: `dbBackend = "postgresql"` + `configurePostgres`,
tailnet-only `domain`, port referenced from
`config.services.vaultwarden.config.ROCKET_PORT` in the vhost (no
duplicated numbers), and secrets via a sops template rendered to an
`environmentFile` (`ADMIN_TOKEN`, `SSO_CLIENT_SECRET`). SSO wiring:
`SSO_ENABLED` + `SSO_ONLY` against an authentik OIDC app — login through
the IdP, while the vault encryption password stays client-side by
Bitwarden's design. SSO is severable: drop the `SSO_*` keys and the
module stands alone with local accounts.

**authentik** (`nixos-modules/authentik.nix`, via the `authentik-nix`
flake module) — small: nginx integration on the tailnet name,
`disable_startup_analytics`, secret key via sops template, and the
public serverAlias added with `forceSSL`/`useACMEHost` mkForce'd for the
external-to-tailnet case. Consumers follow one convention:
`oidc/clientSecrets/<app>` sops secrets; forgejo takes
`ENABLE_AUTO_REGISTRATION` with `DISABLE_REGISTRATION = true` (accounts
only via SSO) and `after = [ "authentik.service" ]`.

**headscale vs hosted Tailscale** — the real decision if any of this is
adopted. Self-hosting the control plane buys SSO-controlled tailnet
login and no dependence on Tailscale Inc., and costs running a
public coordination server (nephele) plus the embedded DERP relay
(`derp.server` with `verify_clients`, UDP 3478 STUN). The current
hosted-Tailscale setup makes headscale unnecessary; everything else in
the stack (tailnet-only vhosts, real certs, public-proxy pinholes,
vaultwarden, authentik) works identically on hosted Tailscale.
(Decided 2026-08-25: control plane stays hosted Tailscale.)

**Sizing note**: the whole stack is ~470 lines of module code across
vaultwarden, authentik + public proxy, headscale, golink, forgejo,
radicale, immich-public-proxy. A Michel version — vaultwarden
tailnet-only on helium behind the existing Tailscale, no headscale, IdP
optional — would be one module of about 50 lines plus the secrets
story, which remains the actual prerequisite (admin token at minimum).

Smaller bits spotted on the way: `tailscale-golink` (go/short-links
service that joins the tailnet itself via an auth key from sops);
radicale with bcrypt `htpasswd` auth from a sops file and persistence
resolving the storage dir from config with a `hasAttrByPath` fallback.

### Supporting service patterns

- **Reverse-proxy self-registration** (both repos independently: ambroisie
  `modules/nixos/services/nginx/default.nix`, sebastianrasor
  `nixos-modules/reverse-proxy.nix` + `acme.nix`) — one module exposes a
  `proxies`/`virtualHosts` option; every service file writes its own vhost
  in, and the proxy/ACME/SSO wiring stays in one place (sebastianrasor
  collects `attrNames cfg.proxies` into a single cert's
  `extraDomainNames`). Services-register-into-a-sibling-module fits the
  dendritic one-feature-per-file philosophy; only relevant once a server
  hosts multiple HTTP services. Same family as smh's homelab Caddy bundle
  (fork survey Tier 3).
- **Caddy `vpn` flag on self-registered vhosts** (GaetanLepage) — the one
  new bit beyond the reverse-proxy pattern above: a `vpn = true` flag
  emits a `@vpn remote_ip <subnet>` matcher so a vhost has public TLS but
  only answers over the tunnel. Tailnet-equivalent idea for the
  exposure axis.
- **Webhook-only public vhost** (sebastianrasor
  `buildbot-webhook-public-proxy.nix`) — public vhost proxying only
  `locations."/change_hook/"` to a tailnet-internal service; template
  for exposing one path while the rest stays tailnet-only.
- **nginx vhost assertion suite** (ambroisie `services/nginx/`) —
  eval-time asserts: exactly one of port/root/socket/redirect per vhost,
  and (via a `countValues` lib helper) no port or subdomain claimed
  twice, each with a named message. Steal for any future vhost
  self-registration module.

## Sandboxing and agents

- **agentspace — sandboxed agent microVMs** (shazow `vms/agentspace/`,
  library at `github:shazow/agentspace`): run coding agents in
  full-autonomy mode inside a QEMU/KVM microVM instead of on the
  workstation. `mkSandbox` composes: per-project "spaces" mounted into
  `$WORKSPACE` (one sandbox per project, or cwd by default), the host
  `/nix/store` shared read-only over virtiofs with an overlay on top
  (guest gets the whole host package universe, no image bloat, `nix run
  nixpkgs#foo` mostly cached), file injection over a guest-agent socket,
  host notifications on suspend/resume, per-VM persistence dirs, and the
  agent harness + toolchain baked in. A sandbox-specific AGENTS.md tells
  the agent it's in a VM ("never nix-collect-garbage, the store is
  overlayfs"). Bonus helper: `packagesFromDevShell` concatenates a
  project devShell's buildInputs into the VM's systemPackages so the
  sandbox carries the project toolchain automatically. Constraint:
  x86_64-linux/KVM — no nested virt under Fusion on Apple Silicon, so
  the natural home is helium; the concept also ports to the Apple
  container/Virtualization.framework route (halfwhey item below).
- **Socket-activated virtiofsd `/nix/store` share** (shazow
  `modules/virtiofsd-nix-store.nix`): the supporting piece — a
  systemd-hardened, socket-activated virtiofsd serving `/nix/store`
  read-only to local VMs; his microvm variant shows a rootless 9p
  fallback. Independently useful for fast throwaway VMs on any Linux
  host.
- **halfwhey/nix-apple-container** (arianvp survey) — nix-darwin module
  (`services.containerization`) for Apple's `container` runtime: Nix-packaged
  CLI (Apple's signed installer pkg, pins 1.1.0), Kata kernel as a
  derivation, auto-started runtime, per-container DNS (`foo.test`),
  declarative container reconciliation, optional Linux-builder containers as
  a lighter alternative to the qemu linux-builder. Natural runtime for the
  container-server image, and would replace the hand-installed
  /usr/local/bin/container pkg. Deferred (2026-07-10) because: v0.0.6 with
  open launchd bootstrap bugs (#8, #9); the module owns the runtime and
  deletes undeclared containers (fights ad-hoc `container machine` use);
  "VPN or tunnel interfaces break vmnet port forwarding" (we run tailscale);
  recommends macOS 26 and neon is on Sequoia. Revisit after the Tahoe
  upgrade or when container-server layering starts.
- **`programs.mcp` as single MCP registry** (drupol) — define each MCP
  server once (command via `lib.getExe`, env, disabled by default), fan
  out via `enableMcpIntegration` on codex/opencode/vscode/zed. The
  portable idea for users/mich/claude/.
- **mcp-gateway** (drupol) — one HTTP endpoint aggregating all registered
  stdio servers (systemd user service, YAML generated from
  `programs.mcp`).
- **litellm as a Copilot proxy** (drupol) — GitHub Copilot subscription
  exposed as an OpenAI-compatible endpoint (`github_copilot/<model>` +
  editor headers); agent tools' self-update pinned off since nix manages
  the binaries.
- **Agent skills pinned as flake inputs** (drupol
  `modules/ai-local/skills.nix`) — non-flake inputs (skill collections)
  symlinked into the agent's skills dir via a readDir helper;
  third-party Claude skills become lock-pinned and update with `nix
  flake update`. Directly relevant to the nix-managed claude config in
  users/mich/claude/.

## GCE projects (self-originated)

- **GPU GCE image variant (`gce-gpu`)** — a separate x86_64 image for GCP GPU
  instances (T4/L4/V100/A100/H100; GCP has no aarch64 GPUs), layering the
  NVIDIA datacenter driver + CUDA onto the existing base+server+gce
  composition. Deliberately NOT baked into the generic `gce-image`: the
  driver is unfree, a large closure, and pinned to a kernel+CUDA version per
  GPU generation. Shape: a `gpu` aggregate (`hardware.nvidia.package =
  config.boot.kernelPackages.nvidiaPackages.dc` or `.production`,
  `hardware.graphics.enable`, `nixpkgs.config.allowUnfree = true`, headless —
  no xserver, just the kernel module + `nvidia-smi` + CUDA libs) plus
  `packages.x86_64-linux.gce-gpu-image`. Open decisions: driver channel
  (`dc` datacenter vs `production`), and whether to bake the CUDA runtime
  into the image (turnkey but big) or leave it to per-workload nix shells
  (lean). Raised 2026-07-22 during the GCE image work; build after the base
  image is boot-tested.
- **Spot/preemption graceful drain** (only if running Spot VMs). Spot
  instances get a ~30s notice via the metadata server; a systemd watcher can
  drain/flush before the ACPI soft-off.
- **Cloud Ops Agent / logging** (production observability, heavier). Ship
  metrics + logs to Cloud Monitoring/Logging. No clean nixpkgs module (Google
  binary), so this is the most involved of the set.
- **tailscale state + imaging** (sebastianrasor `tailscale.nix`) —
  `--encrypt-state=false` when persisting/imaging
  `/var/lib/tailscale/tailscaled.state`; the TPM-bound default makes
  persisted state non-restorable. Relevant to the GCE image + tailscale
  auto-join item. (Per the 2026-08-25 role split, exit nodes don't keep
  state at all — this matters only if a stateful node is ever imaged.)

## Other decisions

- **nix-homebrew** (dustinlyons, wimpysworld) — `zhaofengli/nix-homebrew`
  installs Homebrew itself declaratively and can pin the core/cask taps
  in flake.lock (`mutableTaps = false`) — the cask layer becomes
  reproducible and rolls back with the flake. Real decision: it changes
  `brew update` semantics (formula defs only move on lock update;
  CVE-fix lag) and sits oddly with our deliberate `cleanup = none`
  looseness.
- **srvos modules (nix-community)** (ryan4yin's references) — a
  maintained flake input of opinionated, composable NixOS profiles:
  `common`, `server`, `desktop`, mixins (`terminfo`,
  `trusted-nix-caches`, `nix-experimental`, `systemd-boot`, `mdns`, …),
  roles (`nix-remote-builder`, `github-actions-runner`). Concrete uses
  here: `mixins-terminfo` (fixes broken terminfo when SSHing into the
  dev VM), `mixins-trusted-nix-caches` (curated public binary cache
  list); `server` could slim the WSL/headless-VM hosts, though it may
  fight our desktop VM. One extra input; modules are small and readable,
  so audit-then-adopt is realistic.
- **Scripts as first-class packages** (wimpysworld, srid): each helper
  script is a dir with `default.nix` wrapping `pkgs.writeShellApplication`
  (PATH-pinned runtimeInputs, build-time shellcheck), auto-imported into an
  overlay so every `packages/foo.nix` is `pkgs.foo` and a flake package.
  We already autowire modules via import-tree; this extends the same
  convention to scripts — candidates: the Makefile's inline shell, future
  VM helpers. Related debugging one-liner (wimpysworld): `nix build
  .#nixosConfigurations.<host>.pkgs.<pkg>` builds a package exactly as that
  host sees it, overlays and allowUnfree included.
- **Flake templates for project scaffolding** (traxys) — `flake.templates` +
  `templates/` (rust/gui/webapp/webserver), each shipping `flake.nix` +
  `.envrc` + `.gitignore`, consumed as `nix flake init -t my#rust` (with the
  registry alias above). Makes our stated "per-project flakes + direnv"
  convention a one-liner instead of copy-paste. Adopt the mechanism with our
  own content (go, python); the `users/mich/shells/` trio
  (biotools/security/cowrie) could graduate to templates while staying
  usable as shells. (Partially adopted — `templates/` exists; the shells
  graduation is the open half.)
- **WSL improvements** (fork survey; we have a `make wsl` target):
  - `cloudsbit` `machines/wsl.nix` — `wsl.interop.register = true`,
    `boot.tmp.useTmpfs = false` (fix for slow Go builds).
  - `jiaqiwang969` `machines/wsl.nix` — `programs.nix-ld` with a libraries list
    (run unpatched dynamic binaries), remote Cursor/VSCode-server over SSH, and a
    self-contained NVIDIA-CUDA-on-WSL2 block. Also a `lib/mksystem.nix` import-order
    fix (machineConfig before the WSL module).
  - `nrolland` `machines/vm-shared.nix` — `programs.nix-ld.enable` for the dev VM
    too. (Ignore the `auto-optimise-store-max-*` keys in the same commit — not real
    nix.conf settings; only `auto-optimise-store = true` is genuine.)
- **Parallels on Apple Silicon** (sammyjoyce fork) — `overlays/prl-tools.nix` +
  `machines/hardware/linux-6.12.patch` + `parallels.nix`. Bumps prl-tools and ports
  the guest kernel module to the Linux 6.12 folio API. Only relevant if we switch
  off VMware Fusion.

---

# 5. Reference — patterns to crib when the situation arises

## systemd service patterns

- **DynamicUser + impermanence, the 0700 trap** (sebastianrasor
  `nixos-modules/core.nix` + `actual.nix`) — persist `/var/lib/private`
  itself instead of chasing each DynamicUser StateDirectory, with an
  activation script that pre-creates it `chmod 0700` (systemd refuses
  DynamicUser state dirs otherwise). The sharp edge to know before any
  impermanence adoption.
- **Secrets to services via `LoadCredential`** (sebastianrasor
  `cheaters-swear-jar.nix`) — `LoadCredential` +
  `Environment=FOO_PATH=%d/credName` with DynamicUser, instead of
  EnvironmentFile or owner-chowned secret files. Cleanest
  secret-to-service pattern seen; backend-agnostic.
- **nginx resolves tailnet upstreams at runtime** (sebastianrasor
  `reverse-proxy.nix`) — `proxyResolveWhileRunning = true` + `resolver
  .addresses = [ "127.0.0.53:53" ]` so nginx doesn't fail at boot when
  tailscale DNS isn't up yet. Direct fit for proxying over the tailnet.
- **`RequiresMountsFor` on services with network mounts** (sebastianrasor
  immich/jellyfin modules) — binds a service to its NFS/bind mounts,
  works with automounts; the guard the lazy-automount item lacks.
  Related: persist only `${cacheDir}/transcodes` — persisting a subpath
  of a cache dir instead of the whole state dir.
- **Chicken-and-egg bootstrap oneshot** (sebastianrasor `headscale.nix`)
  — a service that depends on an IdP behind the network it provides:
  start degraded (`only_start_if_oidc_is_available = false`), companion
  oneshot probes the issuer until reachable, then restarts. Generic "A
  needs B, B needs A's network" pattern.
- **`restartIfChanged = false` for long-job services** (both repos
  independently: sebastianrasor buildbot-master, ambroisie
  drone/woodpecker runners) — a deploy doesn't kill in-flight CI builds.
- **Sandboxed nix-capable CI runner** (ambroisie
  `services/drone/runner-exec/`, `woodpecker/agent-exec/`) —
  `confinement.enable = true` with explicit `BindPaths` (nix daemon
  socket, nscd) and `BindReadOnlyPaths` (passwd, ca-bundle, `/etc/nix`,
  `/nix`), `NIX_REMOTE=daemon`; hardening relaxed precisely per runtime
  (`SystemCallFilter` mkForce, `MemoryDenyWriteExecute = false` for
  node).
- **Resource caps on flaky services** (ambroisie transmission/jackett) —
  `MemoryMax = "33%"` / `MemoryHigh`, `TimeoutStopSec = "5m"` to let
  work finish on stop.
- **tmpfiles secret provisioning** (ambroisie `services/lohr/`) —
  `systemd.tmpfiles.settings` with `d` (0700 `~/.ssh`) and `"L+"`
  symlinking a secret into place — declarative key install for a service
  user, no activation script.
- **Cross-host config reference** (sebastianrasor `gate.nix`) —
  `self.nixosConfigurations.<host>.config.services...` used inside
  another host's proxy config so proxy and backend can't drift; same
  file: sops template `restartUnits` bounces the service when the secret
  changes.
- **Small service one-liners** (ambroisie) — grafana
  `admin_password = "$__file{...}"` (native file interpolation);
  parameterized module template (`starr.nix` as a function instantiated
  per service, enables cascading from an `enableAll` master).

## Security and network patterns

- **Reverse-proxy SSO recipe** (ambroisie nginx + paperless modules) —
  complete `auth_request /sso-auth` pattern: internal subrequest
  location, `error_page 401` redirect to the login host with a `go=`
  return URL, username forwarded as `X-User`, per-app ACL via an
  `X-Application` header; app side consumes
  `PAPERLESS_ENABLE_HTTP_REMOTE_USER`.
- **ACME sharp edges** (both) — ambroisie: wildcard DNS-01 cert with
  `dnsPropagationCheck = false` and
  `LEGO_DISABLE_CNAME_SUPPORT=true` when a wildcard CNAME exists; nginx
  reads certs via membership in the `acme` group. sebastianrasor:
  `defaults.dnsResolver = "1.1.1.1:53"` forces DNS-01 lookups past
  split-horizon local resolvers.
- **fail2ban from journald, no log files** (ambroisie, ~12 services) —
  jail + filter with `journalmatch = _SYSTEMD_UNIT=X.service`;
  `iptables-allports` for non-HTTP services; `ignoreIP` for VPN subnets;
  komga shows raising an app's log level solely so fail2ban has lines to
  match.
- **Wireguard peer registry** (ambroisie `services/wireguard/`) — one
  peer list where `clientNum` derives v4+v6 addresses; two interfaces
  (full-tunnel and internal-only) made mutually exclusive with
  reciprocal systemd `conflicts`; on-demand start (`wantedBy = mkForce
  [ ]`) plus a polkit rule letting wheel start/stop exactly those units.
  File for a future helium/nitrogen/laptop mesh.
- **WireGuard IPAM in nine lines** (GaetanLepage) — hub peers generated
  from a pure attrset `pubkey → last-octet` (`peers.nix`); client aspect
  is an options module choosing full-tunnel wg-quick vs split-tunnel
  kernel wireguard. Reference material (we're on tailscale).
- **VPN-only firewall scoping** (ambroisie `services/adblock/`) —
  `networking.firewall.interfaces."${iface}".allowedUDPPorts = [ 53 ]`:
  expose a service on one interface only; unbound with DoT upstream and
  an adblock hosts file compiled to `local-zone: static` entries.
- **Passwordless pam_u2f** (sebastianrasor `pam.nix`) — authfile built
  at eval time from users × registered keys, `unixAuth = false` for a
  hardware-key-only box; complements the pam_rssh item.
- **Misc nginx per-app tweaks** (ambroisie) — `client_max_body_size 0`
  on import/export endpoints, `proxy_read_timeout 1d` for long-lived
  websockets, `proxy_buffering off` for media streaming; a catch-all
  `"_"` vhost 302-redirecting unknown subdomains to the apex.
- `programs.ssh.settings` generated via `mapAttrs`/`genAttrs` from
  hostname maps, wildcard `*.domain` entry for a whole cluster.
  (GaetanLepage)
- **DNS with DoT** (mightyiam) — resolved with `DNSOverTls =
  "opportunistic"` plus explicit Cloudflare+Google v4/v6 servers; and
  `services.paretosecurity.enable` (automated security-posture checks;
  exists for nix-darwin too).

## Storage, impermanence, databases

- **Impermanence disk topology** (sebastianrasor azalea/nephele
  hardware configs) — single real fs at `/nix/persist` (`neededForBoot`,
  `nofail`) with `/nix/store` and `/nix/var` bind-mounted out of it
  (`depends`), swapfile declared inside the persist fs, explicit
  `size=1G` on the tmpfs root of a small server.
- **postgres upgrade escape hatch** (ambroisie `services/postgresql/`) —
  transient `upgradeScript` option installing an `upgrade-pg-cluster`
  script computed from the current config (old/new bin+data dirs,
  `pg_upgrade`, prints follow-ups). Turn on, migrate, turn off.

## lib and module mechanics

- **Option-typing tricks** (sebastianrasor `nixos-modules/persistence.nix`
  + home variant): `lib.types.coercedTo str (d: { directory = d; }) attrs`
  lets one list accept bare strings or attrsets; `lib.optionalAttrs
  (options.home ? persistence)` makes a bridging HM module no-op when the
  NixOS side didn't load its counterpart.
- **Small lib helpers** (ambroisie `lib/`) — `countValues` (duplicate
  detection for assertions), `recursiveMerge` (foldl recursiveUpdate for
  composing config fragments), `renameAttrs`.
- **Pure-Nix IPv4/CIDR lib** (ambroisie `lib/ip.nix`) — `parseSubnet4`
  with `nth`/membership/eval-time warnings; only if peer addresses or
  static network config ever get generated from a subnet definition.
- **Cross-instantiating a callPackage derivation** (sebastianrasor
  `buildbot-jobs.nix`) — `.override (oldArgs: builtins.intersectAttrs
  oldArgs crossPkgs)` re-targets a package to another pkgs set without
  re-plumbing its arguments.
- **Cross-arch CI builds via `extendModules`** (sebastianrasor
  `buildbot-jobs.nix`) — build every nixosConfiguration on one builder
  arch by overriding only the build platform: `cfg.extendModules { modules
  = [{ nixpkgs.buildPlatform = system; }] }`, plus a
  `compatibleCrossBuild` predicate that skips darwin↔linux pairs. Files
  against the deliberate eval-only CI decision (docs/build-venues.md);
  this is the clean mechanism if that ever changes.
- **Arch-filtered build checks** (GaetanLepage
  `modules/flake/hosts/checks.nix`) — `checks.nixos-hosts` =
  `symlinkJoin` over each host's `finalPackage` filtered by `cfg.system
  == system`, so `nix flake check` builds every same-arch host and never
  pulls foreign-arch closures; same filter on deploy-rs checks;
  `checks.devshells` likewise. The build-level sibling of our eval-only
  CI, composable per-arch.
- **`flakeArgs:` file idiom** (GaetanLepage) — a module file written as
  `flakeArgs: { flake.modules.nixos.x = ... }` reaches flake-level
  inputs/config without shadowing module args.
- **nixd fed the repo's own option sets** (sebastianrasor
  `home-modules/vscodium/`) — point the language server's
  `options.nixos.expr` / `options.home_manager.expr` at this flake's
  actual configurations so completion knows the real merged option tree.
  Editor-agnostic.
- **`/etc/nix/inputs` symlinks for nixPath** (ambroisie
  `modules/nixos/system/nix/default.nix`) — `environment.etc` symlinks per
  flake input with `nix.nixPath = ["/etc/nix/inputs"]`; an alternative
  mechanism to the direct nixPath pin worth comparing.
- **`__curPos.file` self-reference** (mightyiam `modules/lib.nix`) — a
  module referencing its own repo-relative path in generated docs;
  survives file moves. Niche.
- **`+flag` filename convention** (dendrix takeaway) — `+flag`/`-flag`
  filename markers + import-tree `.filter` as a way to publish/select
  feature subsets of a module tree.
- **Reusable module templates** (fork survey):
  - `smh` `modules/homelab/` — options-gated service bundle (shared media group +
    gid, NFS automount, tmpfiles rules, Caddy reverse proxy keyed off one `domain`).
    Good "bundle imported per machine" pattern even if we don't run the arr-suite.
  - `cgubbin` `programs/neovim/default.nix` — treesitter grammars built from nixpkgs
    (`withPlugins` + `symlinkJoin`) and symlinked into runtimepath, so nothing
    compiles at runtime. Also the `programs/` (vs `users/<name>/`) convention for
    shareable program modules.
  - `sandangel` `programs/kubeswitch.nix` — clean custom HM module generating shell
    init + bash/zsh completions via `runCommand`. A template for any "needs shell
    init + completions" CLI.
- **Config test harness** (smallstepman fork) — `tests.bats` + `Justfile` +
  `scripts/external-input-flake.sh`. A bats suite tag-filtered per platform
  (`vm`/`darwin`/`wsl`), run in parallel, with a wrapper-flake trick so `nix
  eval/build` can test against generated inputs.
- **Expose HM packages as flake outputs** (moinessim fork `flake.nix`,
  `mkHomeManagerPackages`). Converts `home.packages` into
  `packages.<system>` so individual tools can be `nix build`-ed / cached
  without a full rebuild. Helper is fiddly; idea is sound.

## Home-module mechanics

- **`pkgs.emptyDirectory` as "configure, don't install"** (ambroisie
  work-machine homes) — `git.package = pkgs.emptyDirectory` (or a stub
  symlinking `/usr/bin/<tool>` with `meta.mainProgram`) so home-manager
  writes config for host-provided binaries. Exactly the WSL/corporate
  machine case.
- **`lib.hiPrio` wrapper shadowing** (ambroisie steam module) — shadow a
  package's binary with a same-name `writeShellScriptBin` wrapper (e.g.
  relocating its dotfile mess via `HOME=`) while keeping the package
  installed.
- **Kernel-keyring token caching** (ambroisie `pkgs/bw-pass/`) — caches
  a CLI session token via `keyctl add/request/timeout` (15-min timeout)
  — sudo-free secret caching for any CLI.
- **Firefox de-noising pref list** (ambroisie `modules/home/firefox/`)
  — the comprehensive block disabling `browser.ml.*`/AI surfaces,
  pocket, sponsored content, form-autofill, and the built-in password
  manager; a crib sheet independent of the declarative-Firefox
  machinery.
- **Imperative tools pinned to input revs** (vic doom.nix) — activation
  script compares the installed tool's rev to `inputs.<x>.rev`, no-ops
  when equal, else fetches exactly that rev. Recipe for tools that
  insist on managing their own directory.
- **Compact multi-account mail definition** (ambroisie
  `modules/home/mail/accounts/default.nix`) — accounts built from a
  `mkConfig` helper + provider flavor attrsets (`flavor = "migadu.com"`
  etc.), `passwordCommand = [rbw-pass "Mail" name]` — if mail is ever
  declared in nix.

## Packaging patterns

- **Gradle via `mitmCache`** (sebastianrasor `packages/*/`) —
  `gradle.fetchDeps` + `deps.json`, `-Dorg.gradle.java.home` pinning,
  `meta.sourceProvenance`; `fetchGit { ref = "refs/pull/N/head"; }` to
  pin an unmerged upstream PR.
- **Version from the project's own metadata** (sebastianrasor) — parse
  `gradle.properties` (lib.pipe) or `Cargo.toml` (`fromTOML`) for
  pname/version/mainProgram instead of duplicating them.
- **Compose-don't-mutate app dirs** (sebastianrasor
  `legacy-packages/fabricmc-servers/`) — plugins/mods via `symlinkJoin`
  injected through a `makeBinaryWrapper` flag; `passthru.updateScript`
  (jq against the upstream version API) emitting a `versions.json`;
  `fetchMavenArtifact` pointed at any maven-shaped API as a generic
  pinned-artifact fetcher.
- **Build-time config assets** (sebastianrasor `gate.nix`) — `fetchzip`
  + imagemagick in a small derivation, store path referenced from the
  config template: derive assets, don't commit binaries.
- **Self-registering browser helper** (ambroisie `pkgs/ff2mpv-go/`) —
  postInstall runs the built binary with `--manifest` to generate its
  own native-messaging JSON into `$out`.
- **Nested package override** (sebastianrasor `intel-arc-a380.nix`) —
  `jellyfin-ffmpeg.override { ffmpeg_7-full = prev.ffmpeg_7-full
  .override { ... }; }` — reference for the gce-gpu item if QSV/VAAPI
  plumbing ever comes up.
- **Overlay/packaging templates** (fork survey) — `moinessim`
  `overlays/vpnutil.nix` — `fetchzip` + `mkDerivation` for a prebuilt
  macOS binary with `meta.platforms = darwin`. Template for packaging a
  prebuilt Darwin tool.

## GPU / AI hosting

- **DGX Spark llama-cpp config** (GaetanLepage `modules/hosts/spark/_nixos/
  llama-cpp.nix`) — gpt-oss-120b MXFP4 via `hf-repo`, GB10 tuning flags
  with citations, bound to the wireguard address only, plus a systemd
  ordering fix for the VPN-bind race. Feeds the dgx-spark/gce-gpu
  memory item.

---

# 6. Package and app candidates

- **hyperfine** for benchmarks
- **fq** (https://terminaltrove.com/fq/) — jq for binary formats

## CLI, cross-platform (traxys survey)

- **oscclip** — OSC52 clipboard: copy from a shell inside the VM or over
  SSH straight to the Mac clipboard, terminal-mediated, no X forwarding.
  Ghostty supports OSC52 — a neat fit for the SSH-into-VM workflow.
  (Superseded by ambroisie's osc52/osc777 scripts, section 2.)
- **nix-tree** — interactive closure browser; answers "why is this VM image
  huge" better than `nix path-info -rsSh`.
- **nix-du** — GC-root disk usage graph; pairs with `make gc`.
- **nix-init** — scaffolds a derivation from a URL; handy for packaging
  one-offs.
- **nixpkgs-review** — build all packages a nixpkgs PR touches; only if we
  start contributing to nixpkgs.
- **xdg-ninja** — one-shot audit for $HOME dotfile clutter; we set
  `xdg.enable` already, this finds the stragglers and suggests the env vars
  he sets by hand (CARGO_HOME, RUSTUP_HOME, PSQL_HISTORY, a
  history-in-XDG pythonrc, …).

## CLI (six-config survey)

- **nvd**, **nix-diff** — closure/derivation diffing (nvd also comes free
  with nh).
- **plistwatch** (darwin) — live-diff macOS `defaults` to discover which
  domain/key a System Settings toggle writes; how you grow
  `system.defaults` without guessing.
- **pueue** — queue for long shell jobs with completion notifications;
  useful for serialized big builds in the VM.

## CLI (dendritic sweeps)

- **CLI candidates** — `ripgrep-all` (rg into PDFs/archives), `fx` +
  `jd-diff-patch` (JSON explore/diff), `watchexec`, `gping`,
  `bandwhich`, `ansifilter`, `uni`, `ouch` (one CLI for all archives),
  `git-trim`, `serie` (git graph TUI), `diffnav`, `television`,
  tealdeer with `use_pager = true`.
- From mightyiam's baskets additionally: `dust`, `procs`, `usbtree`,
  `tokei`; `corkscrew` (drupol — ssh through corporate HTTPS proxies via
  `ProxyCommand`); `dysk` (sebastianrasor — modern `df`).

## Packages to consider for `home.packages` (macOS)

### Situational (only if scripted)

- **blueutil** — macOS Bluetooth CLI (power, pair, connect). Earns its slot only
  if a script/Hammerspoon config drives Bluetooth.
- **bluetooth-connector** — Connect/disconnect a specific BT device by MAC.
  Same caveat as blueutil.
- **terminal-notifier** — Native macOS notifications from shell scripts
  (`make build && terminal-notifier -message done`). Cheap to keep, easy to skip.
- **keycastr** — On-screen keystroke overlay. Only for screencasts / pairing.

## Homebrew casks to consider (macOS)

### macOS quality-of-life — high value, brew-only

- **betterdisplay** — Forces HiDPI on non-Retina external monitors, custom
  resolutions, dummy displays. Essential with any external display.
- **bluesnooze** — Stops Mac from reconnecting to BT audio on sleep/wake.
  Solves a real AirPods annoyance.

### Useful when the use case fits — brew-only

- **deskpad** — Virtual second display for screen sharing without exposing the
  real desktop. Niche but excellent when needed.
- **glance-chamburr** — QuickLook plugin bundle (Markdown/code/JSON preview on
  spacebar). Low-cost QoL.
- **istherenet** — Menubar internet-up indicator. Redundant if `stats` is
  installed (its network module covers this).

### Source from nixpkgs, not brewCasks

- **beekeeper-studio** — SQL GUI. Only if SQL databases are a regular thing.

### Dev tooling — judgment calls

- **yaak** — Postman/Insomnia alternative (HTTP/gRPC). Worth it if APIs get
  tested regularly; brew-only as far as I know — verify.

### Casks spotted in another config — candidates

- **cleanshot** — Screenshot + screen-recording + annotation + scrolling
  capture. Paid app, no real free equivalent that matches it.
- **arto** — Markdown reader (`arto-app/tap/arto`). Niche; keep only if it's
  the actual daily Markdown viewer over Obsidian / a browser preview.
- **sdformatter** — SD Association's official formatter. Keep only while
  actively flashing SD cards (Raspberry Pi, cameras, etc.).
- **blu-ray-player-pro** — Blu-ray disc playback. Keep only with an optical
  drive in active use; otherwise pure dead weight.

## Mac App Store apps (`masApps`) — candidates

### No-brainer keepers (free, native, best-in-class)

- **Hex Fiend** — Best free hex editor for macOS. Open-source.
- **The Unarchiver** — Handles archive formats the built-in macOS unarchiver
  can't (RAR, 7z, etc.).
- **Gifski** — High-quality video-to-GIF converter (Sindre Sorhus).
- **Actions** — Extra Shortcuts actions (Sindre Sorhus). Worth it for any
  non-trivial Shortcuts use.

### Safari extensions (complementary, not overlapping)

- **AdGuard for Safari** — Network/element blocking.
- **Hush** — Cookie/consent banner dismisser.
- **Consent-O-Matic** — Aarhus University consent auto-handler; complements
  Hush rather than duplicating it.
- **Userscripts** — Tampermonkey/Greasemonkey equivalent for Safari.
- **Refined GitHub** — Significant GitHub UI improvements. Strong keeper.
- **uBlacklist for Safari** — Filter SEO spam from Google results.

### macOS quality-of-life (all small, all useful)

- **Command X** — True cut/paste in Finder (`Cmd+X` actually moves files).
- **Velja** — Per-URL browser routing (Sindre Sorhus). Opens links in the
  right browser based on rules.
- **Shareful** — Adds entries to the macOS Share menu (Sindre Sorhus).
- **Screegle** — Hides notifications during screen sharing. Excellent for
  calls.
- **LadioCast** — Audio routing/mixer; only with BlackHole-style routing
  setups.

---

# 7. Decided against, superseded, or explicitly skipped

Kept for the record so the same paths don't get re-surveyed.

- **den** (`denful/den`) — full aspect framework (aspects as functions
  of host/user context, `includes`, quirks, forward piping,
  angle-bracket `__findFile` tricks). Very active, but one-author, deep
  magic, high churn — vic's own config has been rewritten ~7 times, and
  drupol's blog documents a real host×user cardinality bug den
  introduced (fixed in den#468 by deduping `<class>@<identity>`). Our
  explicit `flake.modules` aggregates avoid that bug class by
  construction. den is what the raw pattern compiles down to; stay on
  the substrate.
- **dendrix** (community module aggregation) — dormant since 2026-01;
  wrong trust/pinning direction (it pins third-party modules, not us).
  Don't consume; read the indexed repos directly.
- **with-inputs / unflake** (npins, no flake.nix; ~3× eval speedup
  claimed) — abandons flake UX and our CI conventions; skip unless eval
  time becomes a real problem.
- Avoid outright: `.addScoped` / `scopedImport` and `__findFile`
  angle-bracket tricks — invisible coupling inside module files.
- **headscale** — decided 2026-08-25: control plane stays hosted
  Tailscale; everything else in the identity stack works identically
  without it.
- **lanzaboote** — the repart+signed-UKI pipeline covers our Secure Boot
  case; lanzaboote solves a different (interactive laptop) case.
- **GaetanLepage's CI** — `nix flake check` runs only on PRs touching
  `flake.nix`/`flake.lock` (paths filter), so module changes land
  unchecked. Keep our eval-all-hosts CI.
- Survey skip notes (ambroisie/sebastianrasor, 2026-08-25): both repos
  are the pre-dendritic generation — personal option namespaces (`my.*`
  / `sebastianrasor.<name>.enable`), hand-rolled readDir autoloaders,
  `importApply` input plumbing — so nothing structural carries over.
  Neither has a darwin, WSL, or aarch64 story. Not applicable and
  skipped deliberately: readDir'd authorized-keys (`keys/` already works
  that way), fish-specific config, laptop lid/power-key logind settings,
  starship tweaks (no starship in this repo), YubiKey gpg-nag
  suppression, plymouth splash, the URL-as-email scraper dodge.
  Territories that came up empty: sebastianrasor has no monitoring,
  alerting, or systemd hardening anywhere (DynamicUser + LoadCredential
  is the only isolation used); ambroisie's hardware/profile modules are
  thin laptop/X11 toggles, and the desktop home modules are
  personalization.
- Dendritic-authors sweep notes: mightyiam has no tmux/atuin config
  (zsh+nushell+starship); drupol and vic are fish users, so shell config
  mostly doesn't port — but vic runs ghostty and Macs, which lands
  squarely on our stack. Ecosystem note: vic's repos moved to the
  `denful` org (old URLs redirect); both vic and drupol have migrated
  off raw dendritic onto vic's `den` framework.
- GaetanLepage skip notes: 8 hosts (5 NixOS + 3 standalone-HM), ~224 nix
  files — though only ~35 named aspects; the "55 aspects" framing
  oversells it. No nix-darwin anywhere (his Mac is plain home-manager).

---

# 8. Survey log

What was surveyed when; sections above carry per-item attribution.

- 2026-06-11 — `ryan4yin/nix-config` + the configs its README references
  (srvos found here).
- 2026-07-06 — `traxys/Nixfiles` (NixOS-unstable + flake-parts, fish +
  Wayland, nixvim).
- 2026-07-07 — six popular configs: `dustinlyons/nixos-config`,
  `Misterio77/nix-config`, `Mic92/dotfiles` (first pass),
  `EmergentMind/nix-config`, `wimpysworld/nix-config`,
  `srid/nixos-config`. Ground rules: infrastructure only,
  personalization excluded, diffed against this config before listing.
  Pre-filtered as already-present: Touch ID + pam_reattach, NixOS doc
  trimming, nix-index/comma, registry-pinned nixpkgs, ControlMaster,
  macOS defaults baseline.
- 2026-07-09 — `Mic92/dotfiles` deep dive (second pass, including the
  plain homeshick dotfiles easy to miss; note his repo has no WSL or
  container-tarball machinery, no Makefile — imperative work lives in a
  pyinvoke `tasks.py` — and has moved off flake-parts onto his own
  `adios-flake`, which is immature and not for us).
- 2026-07-10 — `arianvp/nixos-stuff`.
- (undated, earliest) — `mitchellh/nixos-config` forks survey
  (jseppanen, lucamaraschi, phaer, cdenneen, sandangel, smallstepman,
  futtetennista, cloudsbit, jiaqiwang969, nrolland, sammyjoyce, smh,
  cgubbin, moinessim).
- 2026-07-22 — `Misterio77/Foundry` (successor monorepo; the
  committed-host-pubkeys knownHosts item, the `inputs.self ? rev`
  dirty-tree guard, the lock-bump commit convention, and the
  `sops.age.sshKeyPaths` secrets bootstrap carry over from the
  six-config survey unchanged) and `shazow/nixfiles`.
- 2026-08-20 — Tier-1 batch specced from all of the above.
- 2026-08-25 — `ambroisie/nix-config` and `sebastianrasor/nix-config`,
  four passes: architecture, dotfile layer, deep sweep (services, hosts,
  lib, packaging), and the private identity stack. Same day: the
  dendritic authors — `mightyiam/infra` (+ the dendritic pattern doc),
  the denful/vic ecosystem (`vix`, `den`, `dendrix`, `import-tree`,
  `flake-file`, `flake-aspects`, `checkmate`, `with-inputs`), and
  `drupol/infra` (+ his dendritic writing on not-a-number.io: the
  2025-05 host-first → feature-first rewrite rationale, and the 2026-04
  den evaluation — the best published analysis of the pattern's hard
  edge: host×user cardinality, propagation policy, "hosts include
  infrastructure features; users include experience features" — useful
  vocabulary for aggregate design decisions here regardless of den).
- 2026-08-26 — `GaetanLepage/nix-config` (structural + nuggets, one
  pass) and the dendritic small-tricks sweep (mightyiam, drupol, vix
  dotfile layers). Triage/re-sort of this file the same day.
