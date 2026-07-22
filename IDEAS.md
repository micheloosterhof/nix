# Roadmap (self-originated)

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

---

# Ideas harvested from arianvp/nixos-stuff (2026-07-10)

## Tier 2 — higher value, bigger change or a real decision

- **halfwhey/nix-apple-container** — nix-darwin module
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

- **SSH CA on hardware-backed keys** — the logical next step after the Secure
  Enclave key setup on neon. arianvp keeps two FIDO2 tokens, each holding a
  login key *and* a CA key; each CA cross-signs the other token's login key,
  so losing one token doesn't lock him out. Servers trust the concatenated CA
  pubkeys (`TrustedUserCAKeys`) plus a revocation list (KRL) in git — no
  per-machine authorized_keys sprawl. A new machine means signing one cert,
  zero server-side changes. Our version: the NixOS hosts (helium, oxygen,
  VMs) trust a CA, and each Mac's enclave key gets a cert. His ~20-line
  `authorizedPrincipals` module (`modules/ssh-authorized-principals.nix`) is
  liftable as-is. Complementary: Mic92's *host* CA (one `knownHosts` entry
  with `certAuthority = true` instead of per-host keys) covers the other
  direction of trust.

- **`SSH_SK_PROVIDER` via `environment.variables` in a darwin module** — same
  as the exports now in users/mich/zshenv + bash_env, but system-wide
  (`/usr/lib/ssh-keychain.dylib`), covering non-login contexts too. Optional
  consolidation; the dotfile exports work today.

---

# Ideas harvested from six popular configs

Surveyed the most-starred personal Nix configs not yet covered (2026-07-07):
`dustinlyons/nixos-config` (the big darwin+NixOS starter),
`Misterio77/nix-config` (author of nix-starter-configs), `Mic92/dotfiles`
(sops-nix/nixos-anywhere/srvos author), `EmergentMind/nix-config`,
`wimpysworld/nix-config` (Martin Wimpress), `srid/nixos-config`
(nixos-unified author). Same ground rules: infrastructure only,
personalization excluded, diffed against this config before listing.
Filtered out what we already have (Touch ID + pam_reattach, NixOS doc
trimming, nix-index/comma, registry-pinned nixpkgs, ControlMaster, macOS
defaults baseline). Attribution in parentheses.

## Tier 1 — low-risk wins

- **nh as the rebuild/GC frontend** (Misterio77, EmergentMind, wimpysworld —
  three configs independently). `programs.nh` exists on both NixOS and
  nix-darwin: `nh os|darwin|home switch` wraps rebuilds with nom-style build
  trees and an nvd closure diff; `nh clean all --keep 5 --keep-since 20d`
  expresses keep-count *and* keep-age, which `nix.gc.options` can't. Slots
  behind `make switch`/`make gc` without changing the interface.

- **Pin every flake input into the registry, and blank the global one**
  (Misterio77, EmergentMind, srid, wimpysworld — four configs). We pin only
  `nixpkgs`. `nix.registry = lib.mapAttrs (_: flake: { inherit flake; })
  (lib.filterAttrs (_: lib.isType "flake") inputs)` + matching `nixPath` +
  `flake-registry = ""` makes every `nix run/shell <input>#…` resolve to the
  locked rev — deterministic, offline-capable, no surprise second nixpkgs
  download. wimpysworld's caveat to keep: pinning inputs embeds their source
  trees in the closure (~700 MB), so pin everything on workstations but only
  self/nixpkgs on the container tarball and VM images.

- **Small nix.settings from people who build nix** (Mic92, EmergentMind):
  `warn-dirty = false`, `builders-use-substitutes = true` (remote builder
  fetches from cache directly instead of copy-via-Mac; free win for the
  existing linux-builder).

- **Claude Code hygiene** (srid, dustinlyons): add `permissions.deny` rules
  for `rg`/`find`/`grep` over `/nix*` to the tracked
  `users/mich/claude/settings.json` — stops agents from crawling the store
  and wedging sessions. Optional: the `sadjow/claude-code-nix` flake
  (overlay + its own cache, daily bumps) as an alternative to our
  unstable-overlay claude-code if nixpkgs-unstable ever lags.

- **Rebuild ergonomics one-liners** (EmergentMind): `git add
  --intent-to-add .` before every build (kills the "path does not exist"
  flake gotcha for new files — belongs in `make switch`/`make test`);
  `nix flake update --timeout 5` so one dead input host doesn't hang the
  bump. Plus srid's activation-hang insurance to file away:
  `systemd.services.NetworkManager-wait-online.enable = false` and
  dbus-broker `restartIfChanged = mkForce false` are the two canonical
  "switch hangs" fixes for GUI VMs.

- **Lock-bump commit convention** (Misterio77's AGENTS.md): manual
  flake.lock commits must summarize what actually changed upstream (compare
  the old/new revs, bullet the meaningful commits). The weekly update-lock
  PR already carries the input diff; this is the same rule for hand-run
  bumps. Worth adding to our AGENTS.md alongside the existing "call out
  lock regeneration" rule.

- **inotify watch bump for dev VMs** (dustinlyons):
  `boot.kernel.sysctl."fs.inotify.max_user_watches" = 1048576` — stops
  file-watcher exhaustion with big repos under editors/direnv in the VM.

## Tier 2 — higher value, bigger change or a real decision

- **Dependabot for the GitHub Actions themselves** (dustinlyons): a small
  `.github/dependabot.yml` keeps the pinned `actions/checkout@v5` /
  `cachix/install-nix-action@v31` versions current via PRs instead of
  silently aging. (Leftover from the adopted build-every-closure item.)

- **Fleet SSH config derived from the flake itself** (Misterio77;
  EmergentMind variant). Commit each host's `ssh_host_ed25519_key.pub` next
  to its host file; one module generates `programs.ssh.knownHosts` for
  every configuration name (kills TOFU prompts and known_hosts drift across
  Mac↔VMs↔WSL), and an HM module generates the client matchBlocks the same
  way — add a host, get its SSH entry and trust anchor for free. The
  committed pubkeys later double as sops-nix/ssh-to-age recipients if that
  secrets route is chosen. Companion QoL (srid): an HM-managed `~/.ssh/rc`
  that re-points a stable `~/.ssh/ssh_auth_sock` symlink on each connect, so
  agent forwarding inside long-lived tmux sessions survives reconnects —
  our exact Mac→SSH→tmux-in-VM workflow.

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

- **`pkgs.inputs.<flake>.<pkg>` overlay** (Misterio77): one overlay mapping
  every flake input to `pkgs.inputs.${name}` (its packages for the right
  system). Dendritic modules then use input packages without threading
  `inputs` through specialArgs or hand-picking `system`. Would simplify our
  unstable-overlay plumbing too (`pkgs.inputs.nixpkgs-unstable.gh`).

- **Boot-generation pinning** (EmergentMind): `just pin` copies the current
  systemd-boot entry to `hosts/<n>/pinned-boot-entry.conf` (title
  "PINNED:"), registers a GC root for that generation, and the module
  re-injects it via `boot.loader.systemd-boot.extraEntries` guarded by
  `lib.pathExists`. A known-good generation that survives both GC and
  `configurationLimit` — nice safety rail for the VMs, portable to a `make
  pin` target.

- **Secrets bootstrap specifics** — new material for the open secrets
  decision, from four configs:
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

- **nix-homebrew + mac-app-util** (dustinlyons, wimpysworld — both). (a)
  `zhaofengli/nix-homebrew` installs Homebrew itself declaratively and can
  pin the core/cask taps in flake.lock (`mutableTaps = false`) — the cask
  layer becomes reproducible and rolls back with the flake. Real decision:
  it changes `brew update` semantics (formula defs only move on lock
  update; CVE-fix lag) and sits oddly with our deliberate `cleanup = none`
  looseness. (b) `mac-app-util` is less contentious: trampolines so
  nix/HM-installed `.app` bundles appear in Spotlight and survive store-path
  changes in the Dock — fixes a real papercut with our nix-installed GUI
  apps (Zed).

- **Scripts as first-class packages** (wimpysworld, srid): each helper
  script is a dir with `default.nix` wrapping `pkgs.writeShellApplication`
  (PATH-pinned runtimeInputs, build-time shellcheck), auto-imported into an
  overlay so every `packages/foo.nix` is `pkgs.foo` and a flake package.
  We already autowire modules via import-tree; this extends the same
  convention to scripts — candidates: the Makefile's inline shell, future
  VM helpers. Related debugging one-liner (wimpysworld): `nix build
  .#nixosConfigurations.<host>.pkgs.<pkg>` builds a package exactly as that
  host sees it, overlays and allowUnfree included.

- **ghostty→tmux→nvim file-link opener** (Mic92,
  `home-manager/modules/tmux-open-file.nix`): registers a trampoline as the
  MIME/UTI handler for source files on both OSes (xdg.mimeApps on Linux;
  osacompile-built .app + `duti` on macOS), so clicking a `file://` link
  ripgrep/compilers print in ghostty opens nvim in the active tmux pane.
  We run exactly this stack on both platforms; his header comment documents
  why naive wrappers fail (GUI apps inherit launchd PATH).

- **Per-host runbooks next to host files** (srid): `mod.just` per host —
  backup/restore/health-check sequences as versioned recipes namespaced
  `just <host> <task>`, living beside the host config. Ports to per-host
  Makefile includes; beats a wiki for "how do I poke this box" knowledge.

- **`inputs.self ? rev` dirty-tree guard** (Misterio77): systemd timers /
  automation that should only run from a committed config get `enable =
  inputs.self ? rev` — auto-upgrade or CI-pull machinery silently disables
  itself on a dirty checkout. File next to any future auto-upgrade work.

- **flake-inputs cache-priming derivation** (Mic92): three-line
  `runCommand` interpolating every input's store path, built in CI so all
  input sources land in the binary cache — later checks/rebuilds never
  re-fetch. Adopt together with the already-noted cachix CI item.

## Programs spotted (CLI, cross-platform) — candidates for `home.packages`

- **nvd**, **nix-diff** — closure/derivation diffing (nvd also comes free
  with nh).
- **plistwatch** (darwin) — live-diff macOS `defaults` to discover which
  domain/key a System Settings toggle writes; how you grow
  `system.defaults` without guessing.
- **pueue** — queue for long shell jobs with completion notifications;
  useful for serialized big builds in the VM.

---

# Mic92/dotfiles — deep dive (second pass)

The six-config survey above sampled Mic92; a second full-enumeration pass
(2026-07-09) over his system modules, machines, and — crucially — his plain
homeshick dotfiles (`home/`: .gitconfig, .zshrc, .tmux.conf, .direnvrc — not
home-manager `programs.*`, so easy to miss) turned up more. Same ground
rules. Note: his repo has no WSL or container-tarball machinery, no Makefile
(imperative work lives in a pyinvoke `tasks.py`), and has moved off
flake-parts onto his own `adios-flake` (immature — not for us).

## Tier 1 — low-risk wins

- **`home/.gitconfig` — the densest portable gitconfig surveyed.** Beyond
  the git tweaks already listed above and in the traxys survey:
  `commit.verbose = true` (diff in the commit-msg
  editor), `help.autocorrect = 10`, `am.threeWay = true`, `[credential
  "https://github.com"] helper = !gh auth git-credential` (gh becomes the
  token source; no keychain wiring), SSH commit signing (`gpg.format =
  ssh`), a trailing `[include] path = ~/.gitconfig.local` so per-machine
  overrides win, and aliases `uncommit = reset --soft HEAD^`, `recommit =
  !git commit -eF $(git rev-parse --git-dir)/COMMIT_EDITMSG` (recover a
  failed commit message), `checkout-pr` (fetch `pull/$N/head`).

- **tmux.conf modernisms, remaining bits** (`home/.tmux.conf`):
  `update-environment 'SSH_AUTH_SOCK ...'`, splits opening in
  `#{pane_current_path}`, `escape-time 0`, `detach-on-destroy off`, and a
  tmux-thumbs regex for nix SRI hashes. Bonus: zshrc hashes `$HOST` into a
  tmux `@host_color` so remote sessions are visually distinct.

- **`gh auth token` → nix.conf at activation** (`home-manager/coder.nix`
  163–170): an HM activation step writes `access-tokens =
  github.com=$(gh auth token)` into `~/.config/nix/secrets.conf`; nix.conf
  carries `!include secrets.conf` (soft include — skipped if absent). Same
  goal as EmergentMind's sops variant (six-config survey, secrets bullet)
  but with zero secrets infrastructure — gh is already authenticated here.

- **Offline-aware direnv** (`home/.direnvrc`): checks default route + a 1s
  ping; when offline sets `_nix_direnv_manual_reload=1` so nix-direnv
  serves the stale env instead of trying to evaluate/fetch on a plane.
  Copy verbatim.

- **VM/host one-liners** (machines/, nixosModules/): `pkgs.ghostty.terminfo`
  (terminfo output only) in the VM's systemPackages so ghostty-over-SSH
  works — the lightweight version of the srvos mixins-terminfo idea in the
  ryan4yin survey; `services.journald.extraConfig = "SystemMaxUse=1G"` (cap
  journal growth on small VM disks); `zramSwap.enable = true` (take zram
  alone — his separate zswap module on top is a known anti-pattern);
  `systemd.services.systemd-networkd.stopIfChanged = false` (+ resolved) so
  a `nixos-rebuild switch` over SSH doesn't cut the network under you;
  `services.getty.autologinUser` on the throwaway VM;
  `services.dbus.implementation = "broker"`.

- **sshd-or-reboot watchdog** (machines/bernie): `systemd.services.openssh
  = { wantedBy = [ "boot-complete.target" ]; unitConfig.FailureAction =
  "reboot"; }` — a headless machine whose sshd fails at boot reboots
  instead of sitting unreachable. Cheap insurance for the VMs.

- **claude-code hygiene, his version** (pkgs/claude-code,
  home/.claude/): wrapper exports `SHELL=${pkgs.bashInteractive}/bin/bash`
  (claude picks up broken login shells otherwise); a Notification hook
  rings the terminal bell when permission is needed — pairs with tmux
  bell monitoring.

- **On-demand debug shell on any CI arch**
  (.github/workflows/os-ondemand.yaml): a 20-line `workflow_dispatch`
  workflow whose one step is `mxschmitt/action-tmate` with an OS-choice
  input — an interactive shell on a macos/arm64/x86 runner when CI-only
  failures need poking. Port as-is.

- **zsh micro-patterns** (`home/.zshrc`): `fixssh` (re-export
  SSH_AUTH_SOCK from `tmux show-environment` after reattach — the classic
  stale-agent fix, complements srid's symlink approach in the six-config
  survey), `ssh-ephermal` (`UserKnownHostsFile=/dev/null` — right for
  throwaway VMs), `xalias` (define alias only if the command exists, keeps
  one rc portable across minimal hosts).

## Tier 2 — higher value, bigger change or a real decision

- **`machines/utm-vm/` as a dev-VM template** — almost exactly our VM
  shape, worth reading whole: srvos server base + disko single-disk GPT
  (500M ESP + ext4 root, deliberately not ZFS for a throwaway guest),
  networkd DHCP matched on `matchConfig.Type = "ether"` (portable across
  VMware/UTM/VZ — no interface names; stronger than the name-glob variant
  in the fork survey's networkd item), `nix.settings.max-jobs = mkDefault
  4`, per-VM authorized keys.

- **SSH host-certificate CA instead of per-host knownHosts**
  (darwinModules/openssh.nix): `programs.ssh.knownHosts.<name> = {
  certAuthority = true; hostNames = [...]; publicKeyFile = ./ssh-ca.pub; }`
  works identically on nix-darwin and NixOS; host keys signed once
  (`ssh-keygen -s`, domain principals to avoid "not a listed principal"
  warnings). The alternative to Misterio77's committed-pubkeys approach
  (six-config survey) that survives VM rebuilds without re-committing keys
  — one CA file, rebuilt VMs just get re-signed.

- **Checks aggregate beyond host toplevels** (checks/flake-module.nix):
  besides the per-host toplevels already listed, he folds all
  `self'.packages` (with a blacklist for huge artifacts), per-package
  `passthru.tests`, all `devShells`, and home-manager activation scripts
  into `checks`, so one `nix flake check` covers everything. The
  HM-activation-script-as-check piece is the missing HM coverage in our
  eval tests.

- **treefmt details worth copying** (devshell/): `shfmt.includes = ["*.envrc"
  "*.bashrc"]` formats dotfile fragments, per-directory mypy/ruff for repo
  scripts, and `mkShellNoCC` for a compiler-free (much smaller) dev shell.

- **`system.etc.overlay.enable` + `services.userborn.enable`**
  (nixosModules/workstation.nix) — perl-free /etc and user provisioning,
  faster switches. Newer-NixOS feature; test on one VM first.

- **Pre-warm the next closure** (nixosModules/update-prefetch.nix): hourly
  idle-priority service fetches CI's latest build for this host and roots
  it at `/run/next-system`, so the eventual switch is instant; offline
  guard via `ip r g`. Needs per-host closures in a cache first — pairs
  with the pull-deploy notes in the six-config survey.

- **Rescue recipes for Makefile targets** (tasks.py): kexec any Linux VM
  into a NixOS installer (`nixos-images` kexec tarball), and
  `disko --mode mount` from a rescue system to remount the committed
  layout — the practical "reinstall a broken VM" story once disko lands.

- **Workflow scripts** (home/bin/, pkgs/): `git-pr` (treefmt the branch,
  auto-`git absorb` the formatting fixes into the right commits, push to
  fork, open compare URL), `merge-when-green`, `gh-cleanup` (rule-based
  GitHub notification triage via `gh api /notifications`), and
  `systemctl-macos` (launchctl shim for systemctl muscle memory).

- **flake.nix bits**: `nixConfig.extra-substituters` in the flake itself
  (trust prompted on first build, no host config); `?shallow=1` on
  git-hosted inputs; `renovate.json` with `"nix": {"enabled": true}` +
  an auto-merge workflow — a simpler packaged alternative to the
  update-flake-lock CI noted in the traxys survey.

- **Declarative Mac App Store** (darwinModules/app-store/): `pkgs.mas` + a
  ~40-line activation script diffing `mas list` against a wanted-ID list,
  installing missing and uninstalling unwanted. Complements our masApps if
  drift bothers us.

---

# Ideas harvested from traxys/Nixfiles

Surveyed `traxys/Nixfiles` (2026-07-06): NixOS-unstable + flake-parts,
x86 desktop/laptop/home-server hosts plus a standalone home-manager work
laptop, fish + Wayland (niri/sway/COSMIC), nixvim, and a large Rust/gaming
package zoo. Same ground rules as the surveys below: infrastructure only,
personalization excluded, diff against what we already have before adopting.

## Tier 1 — low-risk wins

- **Git defaults worth stealing** — from his `minimal/hm.nix`, all absent
  here, each a one-liner that helps a rebase-heavy workflow
  `rebase.autosquash` + `rebase.updateRefs` (stacked branches follow along),
  `diff.algorithm = histogram`, `branch.sort = "-committerdate"`,
  `core.untrackedCache`, `fetch.writeCommitGraph` + `core.commitGraph`
  (faster status/log in big repos), alias `fpush = push --force-with-lease`.

- **Conditional git identity** — `includes = [{ condition =
  "gitdir:~/Perso/"; contents.user = {...}; }]` gives per-directory-tree
  name/email overrides. Becomes relevant the moment work and personal repos
  share a machine; zero cost to note now.

- **Self-registry alias** — `nix.registry."my".flake = <this flake>` makes
  `nix run my#...` and `nix flake init -t my#<template>` work from any
  directory without a path. One line next to the existing
  `registry.nixpkgs` pin in `modules/nix-settings.nix`.

- **statix as a third lint** — he formats/lints via treefmt-nix with nixfmt +
  statix; we run nixfmt + deadnix. statix catches semantic antipatterns
  (`if x then true else false`, redundant `inherit`, legacy merge idioms)
  that neither of ours sees. With treefmt-nix now in `modules/checks.nix`,
  adoption is one `programs.statix.enable` line.

- **systemd-oomd on the dev VM** — his `gui/nixos.nix` enables
  `systemd.oomd` with user/root/system slices. A big `nix build` inside the
  VM OOM-freezing the guest is exactly the failure mode this catches.
  Self-contained addition to `modules/vm.nix`.

- **nix-output-monitor for builds** — traxys patches nixos-rebuild to call
  `nom build` (`minimal/nom-rebuild.patch`); the 90% version with zero
  maintenance is adding `nix-output-monitor` to `home.packages` and piping
  in the Makefile (`... |& nom`, or `nom build` where targets run
  `nix build`, e.g. `vm/image`, `wsl`).

## Tier 2 — higher value, bigger change or a real decision

- **Flake templates for project scaffolding** — `flake.templates` +
  `templates/` (rust/gui/webapp/webserver), each shipping `flake.nix` +
  `.envrc` + `.gitignore`, consumed as `nix flake init -t my#rust` (with the
  registry alias above). Makes our stated "per-project flakes + direnv"
  convention a one-liner instead of copy-paste. Adopt the mechanism with our
  own content (go, python); the `users/mich/shells/` trio
  (biotools/security/cowrie) could graduate to templates while staying
  usable as shells.

- **Runtime secrets via Bitwarden passwordCommand** — his
  `personal-cli/hm.nix` wraps `bw get item <uuid> | jq` in `bwPass`/`bwUser`
  writeShellScripts and feeds them to any HM option taking a
  `passwordCommand` (he drives CalDAV auth this way). We already install
  bitwarden-cli and have an open "no secrets management" decision (fork
  survey Tier 2) — this is a fourth option: no new tool, nothing on disk,
  secrets pulled at use time. Limits: needs an unlocked bw session, only
  covers tools with command hooks.

- **CI feeding the cachix cache** — the cache and per-host substituter now
  exist (seeded from the Mac); the unadopted half is CI pushing built
  artifacts, bounded by the 5 GB free tier, so it needs a selective
  pushFilter (e.g. only container-server tarballs), and the `CACHIX_TOKEN`
  secret is already in place. Worth keeping regardless: his `build-status`
  join-job trick, letting one required status check stand in for a whole
  matrix.

## Programs spotted (CLI, cross-platform) — candidates for `home.packages`

Same convention as the package lists at the bottom: adopt selectively.

- **oscclip** — OSC52 clipboard: copy from a shell inside the VM or over
  SSH straight to the Mac clipboard, terminal-mediated, no X forwarding.
  Ghostty supports OSC52 — a neat fit for the SSH-into-VM workflow.
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

---

# Ideas harvested from ryan4yin/nix-config and its references

Surveyed `ryan4yin/nix-config` (NixOS + nix-darwin, ~20 hosts, agenix,
impermanence, Kubernetes homelab) and the configs referenced in its README
(2026-06-11). Same ground rules as the fork survey below: infrastructure only,
personalization excluded, diff against what we already have before adopting.

## Tier 2 — higher value, bigger change or a real decision

- **srvos modules (nix-community)** — the standout find from his references.
  A maintained flake input of opinionated, composable NixOS profiles:
  `common`, `server`, `desktop`, mixins (`terminfo`, `trusted-nix-caches`,
  `nix-experimental`, `systemd-boot`, `mdns`, …), roles
  (`nix-remote-builder`, `github-actions-runner`). Two concrete uses here:
  - `mixins-terminfo` — fixes broken terminfo when SSHing into the dev VM
    from a terminal the guest doesn't know.
  - `mixins-trusted-nix-caches` — curated public binary cache list.
  - `server` could slim the WSL/headless-VM hosts (docs trimming, sane
    defaults), though it may fight our desktop VM. One extra input; modules
    are small and readable, so audit-then-adopt is realistic.

- **`nixos-rebuild --target-host` instead of rsync + remote rebuild** —
  ryan4yin deploys his fleet with colmena (overkill for one VM), but the
  lightweight version of the same idea replaces our `vm/copy` + `vm/rebuild`
  pair: `nixos-rebuild switch --flake .#vm-aarch64-fusion --target-host
  mich@$NIXADDR --use-remote-sudo` builds on the Mac (we already have
  `nix.linux-builder`) and pushes the closure over SSH. No `/nix-config`
  rsync, no flake eval inside the VM, VM never needs the repo. Decision:
  where builds should happen (Mac builder VM vs guest).

- **Minimal installer sub-flake** — addressed differently. We didn't add a
  separate sub-flake; instead `packages.<linux>.installer-iso` bakes the
  provisioning ssh key into the standard minimal installer, and nixos-anywhere
  installs the *full* config directly (building on the Mac's linux-builder or a
  native aarch64 box), so there's no "heavy main flake" problem to route around.

- **agenix as the lighter secrets option** — ryan4yin uses agenix (age keys =
  existing ssh keys, one `secrets.nix` mapping files to recipients). Add it
  to the sops-nix/git-crypt decision list in the fork-survey Tier 2 item:
  fewer moving parts than sops-nix, more structure than git-crypt.

---

# Ideas harvested from mitchellh/nixos-config forks

## Tier 1 — low-risk wins that improve something we already have

- **Auto-load overlays** — `jseppanen` / `lucamaraschi` `lib/overlays.nix`. Reads
  `overlays/` and auto-imports every `*.nix` / subdir-with-`default.nix`, so new
  overlays never need hand-listing. Confirmed not present upstream.

### From `phaer/nixos-vm-on-macos` `modules/nixos/base.nix`

A different VM architecture (headless, ephemeral, Apple Virtualization.framework
with the host store shared over virtiofs), but two boot/networking settings are
hypervisor-agnostic and improve our VMware/Parallels/UTM dev VM. The headline
features (Rosetta, virtiofs store) are bound to their Virtualization.framework
stack and don't port to ours.

- **systemd initrd** — `boot.initrd.systemd.enable = true`. We're on the old
  scripted initrd; the systemd one is faster and more customizable. Drop-in.

- **systemd-networkd + mac DHCP identifier** — `networking.useNetworkd = true`
  with a `10-uplink` network matching `en* eth*` and
  `dhcpV4Config.ClientIdentifier = "mac"`. Replaces our scripted
  `networking.useDHCP`, and the mac-based DHCP identifier gives predictable VM IP
  leases — directly addressing the `vm-shared.nix` comments about Fusion's
  unpredictable `enpXsY` NIC names and flaky NAT DHCP. The stronger of the two.

## Tier 2 — higher value, bigger change or a real decision

- **Declarative disk layout with disko** — done (branch `feat/disko-provisioning`).
  `disko.devices` spec (1 GiB ESP + ext4 root, labels `ESP`/`nixos`) lives in the
  fusion host file with `disko.enableConfig = false` so the runtime fstab is
  unchanged and the host's toplevel derivation stays byte-identical. `make
  vm/provision` runs nixos-anywhere against an ISO-booted VM, replacing the
  `vm/bootstrap0`/`vm/bootstrap` shell (both deleted). A keyed
  `packages.<linux>.installer-iso` supplies the target. Verified end-to-end
  (partition → systemd-boot → reboot); the run also surfaced + fixed a real bug
  (`/host` needed `nofail` or a VM without the share drops to emergency mode).

- **Secret management (we currently have none)** — pick one:
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

- **Pre-commit + lint baseline** — `futtetennista` `.pre-commit-config.yaml` +
  `.github/workflows/repo-checks.yml`: trailing-whitespace, detect-private-key,
  shellcheck, `check-jsonschema`, workflow lint, enforced locally and in CI
  (excludes `secret/`). Matches the NFR pre-commit standard.

## Tier 3 — only if scope expands

- **WSL improvements** (we have a `make wsl` target):
  - `cloudsbit` `machines/wsl.nix` — `wsl.interop.register = true`,
    `boot.tmp.useTmpfs = false` (fix for slow Go builds).
  - `jiaqiwang969` `machines/wsl.nix` — `programs.nix-ld` with a libraries list
    (run unpatched dynamic binaries), remote Cursor/VSCode-server over SSH, and a
    self-contained NVIDIA-CUDA-on-WSL2 block. Also a `lib/mksystem.nix` import-order
    fix (machineConfig before the WSL module).
  - `nrolland` `machines/vm-shared.nix` — `programs.nix-ld.enable` for the dev VM
    too. (Ignore the `auto-optimise-store-max-*` keys in the same commit — not real
    nix.conf settings; only `auto-optimise-store = true` is genuine.)

- **Remote NixOS server deploy** — `nrolland` `servers/scw-stardust/`. Nested
  sub-flake: `make create` provisions a cheap cloud VM via cloud-init + nixos-infect,
  `make deploy` does rsync + remote `nixos-rebuild switch --flake`; minimal disko
  GPT layout; age-based `.sops.yaml`. Plus two reusable modules: `tailscale-server.nix`
  (enable tailscale + correct firewall) and a typed `sshKeys` option module. Good
  template if we ever add a remote box.

- **Parallels on Apple Silicon** — `sammyjoyce` `overlays/prl-tools.nix` +
  `machines/hardware/linux-6.12.patch` + `parallels.nix`. Bumps prl-tools and ports
  the guest kernel module to the Linux 6.12 folio API. Only relevant if we switch
  off VMware Fusion.

- **Reusable module templates**:
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

- **Overlay/packaging templates**:
  - `moinessim` `overlays/vpnutil.nix` — `fetchzip` + `mkDerivation` for a prebuilt
    macOS binary with `meta.platforms = darwin`. Template for packaging a prebuilt
    Darwin tool.

- **Config test harness** — `smallstepman` `tests.bats` + `Justfile` +
  `scripts/external-input-flake.sh`. A bats suite tag-filtered per platform
  (`vm`/`darwin`/`wsl`), run in parallel, with a wrapper-flake trick so `nix
  eval/build` can test against generated inputs.

- **Expose HM packages as flake outputs** — `moinessim` `flake.nix`
  (`mkHomeManagerPackages`). Converts `home.packages` into `packages.<system>` so
  individual tools can be `nix build`-ed / cached without a full rebuild. Helper is
  fiddly; idea is sound.

---

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
