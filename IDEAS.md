# IDEAS.md — triaged backlog

Sorted by actionability (triage 2026-08-26), no longer by survey.
Nothing was deleted in the sort: every idea from the survey sections is
below, verbatim, with its source in parentheses. The survey log at the
bottom records what was surveyed when; the "decided against" section
keeps the explicit don't-adopt verdicts and the surveys' own skip notes.

---

# 1. Specced and ready — Tier-1 batch (2026-08-20)

The cheap wins scattered across the surveys, checked against the repo
and turned into concrete changes. None of what is left is implemented
today: `initrd.systemd`, `useNetworkd`, `nix-output-monitor` and
`programs.nh` appear nowhere in the repo outside this file.

Two source bullets turned out to be wrong or more expensive than
advertised — see nh and registry pinning. Each item below is one commit.

## Batch A — no decision to make

**5. nix-output-monitor on the image targets** (`Makefile`, `home.packages`).
Add `pkgs.nix-output-monitor` to the `fullTools` list in
`users/mich/home-manager.nix`, then swap `nix build` → `nom build` in
`vm/image` (line 222) and `gce/image` (line 247). Verified: `nom build
--no-link --print-out-paths` puts only the store path on stdout, so the
`$(...)` capture in `vm/launch` and `gce/upload` keeps working unchanged.
The `*-rebuild` targets are a separate question — piping them needs
`--log-format internal-json -v |& nom --json`, and if nh (item 9) lands it
already prints an nom-style tree, so leave those alone. No test.

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
set it per host file. `make switch`/`make gc` keep their names and call nh
underneath. Decision: whether to hand GC scheduling to nh. Test: an eval
assertion that exactly one of the two GC mechanisms is enabled per host.

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
networkd integrates with cleanly. Also unlocks `modules/ntp.nix` (added
2026-08-26): timesyncd only receives DHCP-offered NTP servers through
networkd's `UseNTP`, so under scripted DHCP its empty `servers` list means
the fallback pool answers everywhere — the "NTP from DHCP when offered"
half starts working here. Verify by booting fusion and utm and
confirming the lease survives two rebuilds.

## Suggested order

A5 and A7 in either order, one commit each — both eval-only, both
verifiable with `make lint`. Then B8/B9, each carrying its decision.
Then C11, boot the VM, then C12, boot the VM again.

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
- **VM/host one-liners** (Mic92, machines/, nixosModules/):
  `systemd.services.systemd-networkd.stopIfChanged = false` (+ resolved) so
  a `nixos-rebuild switch` over SSH doesn't cut the network under you;
  `services.getty.autologinUser` on the throwaway VM;
  `services.dbus.implementation = "broker"`. → stopIfChanged is batch
  C12; the rest stayed in section 2.
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

- **namaka snapshot tests over rendered configs** (zentralwerk/network
  `flake.nix` checks.namaka + `scripts/generate-tests.sh`): golden-file
  eval tests — snapshot the *rendered* artifact (their bird.conf and kea
  JSON per container; ours would be the bogons nft table, sshd_config,
  the golink unit) so a refactor's blast radius shows up as a reviewable
  text diff instead of a boolean assertion. Sits between our eval-tests
  and a VM boot test; test cases are generated per host, `namaka check ||
  namaka review` to accept changes. namaka is in nixpkgs. Companion
  detail (darwin-modular-services `tests/lib/assertions.sh`, borrowed
  from home-manager's nmt): normalize every `/nix/store/<hash>-name`
  to a zeroed hash before diffing, ~10 lines of sed — the trick that
  lets snapshot fixtures survive nixpkgs bumps.
- **nix-darwin module test suite** (DavSanchez `lib/darwin-tests.nix`
  + `tests/darwin/*.nix`, wired as `checks.aarch64-darwin`) — each
  test file is a darwin module plus a `test` script asserting on the
  built system (grep the generated activation script, inspect
  rendered files, negative-test a whitelist), with `makeTestSuite`
  auto-discovering test files. ~90 lines, copyable; the middle layer
  between the eval tests and nothing for darwin modules with
  behavior.
- **Per-host test VMs via `virtualisation.vmVariant`** (LongerHV
  `nixos/mordor/vm-variant.nix`) — `nixos-rebuild build-vm --flake
  .#<host>` boots the *real host config* in qemu, with a per-host
  `vmVariant` block mkForce-neutralizing only what can't work in a VM
  (VPN interfaces, autologin + known password). The missing middle
  between the eval tests and hardware: smoke-boot nitrogen's or
  helium's config on the Mac's linux-builder, with the stubbed
  assumptions declared in one file.
- **shellspec tests for repo shell libraries** (mitchty `spec/*.sh`
  over `src/lib.sh`) — actual unit tests for shell helpers, run via
  shellspec (in nixpkgs). The `~/.bin` scripts and Makefile helpers
  have no tests today; pairs with the actionlint/shellcheck lint-gate
  item from tjmaynes.
- **Generated docs site from module comments + options JSON**
  (barrucadu `scripts/documentation.sh` + `docs/book.toml`) — module
  header comments plus the evaluated `NIXOS_OPTIONS_JSON` render into
  an mdbook site: per-host pages, per-module pages, full options
  reference with types/defaults/declared-in links. The ABOUTME
  convention here is already the input half; the pipeline makes it
  browsable and drift-proof.
- **Per-alert runbooks keyed by alertname** (barrucadu
  `docs/src/runbooks/`) — when an alert fires, a doc named after it
  says what to do; migrations are step-numbered checklists referencing
  the repo's own tools. The fleet-ops upgrade of the mrkuz
  manual-steps item (§2 macOS list).
- **remote/copy deploys always show "configuration dirty"** (spotted
  2026-08-28 via nitrogen's motd): rsync to /nix-config excludes .git, so
  the on-box flake has no self.rev and provenance.nix falls back to
  "dirty" — the motd can never name the deployed commit. Options: rsync
  .git too (cost: repo size, and dirtiness is then real), have remote/copy
  drop the current `git rev-parse HEAD` into a file the motd reads, or
  deploy by pushing to a bare repo / building from the github URL when
  reachable. Small, but it defeats the point of login-time provenance.
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
- **Claude Code managed-settings layer** (malob
  `darwin/claude-managed-settings.nix`) — nix generates
  `/Library/Application Support/ClaudeCode/managed-settings.json` (the
  highest-precedence settings layer) holding only the path-dependent
  bits: `additionalDirectories` pointing at the nix repo and
  Edit/Write permission allows for it, interpolated per host — Claude
  can always edit the config repo without prompts on any machine.
  Everything else stays in the user-editable settings file. His
  companion `home/claude.nix` reconciles third-party skills from
  skills.sh declaratively on each activation (nuke and repave) and is
  worth reading for the 1Password-FIFO-with-timeout secrets handling
  even though we'd feed it from sops.
- **Third-party agent skills as pinned flake inputs** (madmaxieee) —
  skill repos as `flake = false` inputs with individual skills
  symlinked into the agent config dir: lockfile-pinned versions
  instead of a vendored copy or floating clone. The flake-input
  counterpart to the nvfetcher item in CI micro-patterns; same
  pattern serves editor/shell plugin sources.
- **The four-layer declarative agent stack** (takeokunn
  `home-manager/ai-tools/` — the reference implementation for
  nix-managing Claude Code and friends; supersedes reading the
  scattered items above piecemeal). (1) home-manager's
  `programs.claude-code` module used to full depth: settings,
  `permissions.deny` generated from one shared `bashDenyPatterns`
  list, **PreToolUse guard hooks** (`block-destructive-git`,
  `block-bare-cd`) shipped as typed `hooks.*` options with an
  `assert` tying the hook list to the shared names; agents/commands
  from markdown dirs. (2) **mcp-servers-nix** (natsukium):
  `evalModule` renders MCP config declaratively; one shared server
  definition adapted per-CLI (claude-code/opencode/codex) by a tiny
  converter. (3) **llm-agents.nix** (numtide): daily-updated agent
  CLI packages incl. `ccusage` — alternative to sadjow/claude-code-nix.
  (4) **agent-skills-nix** (Kyure-A): vendor skill repos (anthropics,
  cloudflare, aws, …) as pinned inputs with per-source subdir/depth
  filters and cross-vendor conflict handling — the catalog upgrade of
  the skills-as-flake-inputs item. Caveat from the review: their
  conflict-exclusion regexes are write-only; do set-difference in nix
  instead.
- **Per-identity Claude config via `CLAUDE_CONFIG_DIR`** (jwiegley
  `bin/persona`) — one command flips git identity/signing, `gh auth
  switch`, and the whole `~/.claude` per persona. Related nugget:
  scope a single gh call to another account with `GH_TOKEN="$(gh auth
  token --user X)" gh ...` without switching the global login.
- **Claude Code hygiene** (srid, dustinlyons): add `permissions.deny` rules
  for `rg`/`find`/`grep` over `/nix*` to the tracked
  `users/mich/claude/settings.json` — stops agents from crawling the store
  and wedging sessions. Optional: the `sadjow/claude-code-nix` flake
  (overlay + its own cache, daily bumps) as an alternative to our
  unstable-overlay claude-code if nixpkgs-unstable ever lags.
- **claude-code hygiene, Mic92's version** (pkgs/claude-code,
  home/.claude/): wrapper exports `SHELL=${pkgs.bashInteractive}/bin/bash`
  (claude picks up broken login shells otherwise). The settings.json
  `env.SHELL = /bin/bash` covers this today, but only on darwin and only
  in the hand-synced live file; the wrapper version is nix-managed and
  works on NixOS hosts too.
- **Auto-load overlays** — `jseppanen` / `lucamaraschi` `lib/overlays.nix`. Reads
  `overlays/` and auto-imports every `*.nix` / subdir-with-`default.nix`, so new
  overlays never need hand-listing. Confirmed not present upstream.
- **Docs generated from the config, `--check`ed in CI** (devon-systems/hoenn
  `scripts/generate-niri-keybindings.ts`, plus `generate-host-readmes` for
  the `facter.json` spec tables) — a script parses the real config and
  renders a table into the README between `<!-- BEGIN GENERATED ... -->`
  markers; a `--check` flag re-renders and fails when the checked-in doc has
  drifted, so CI catches the drift instead of a reader. AGENTS.md carries
  one line: "Do not edit text between generated-section markers." Concrete
  shape for the docs-drift test noted-but-unfiled from tjmaynes.

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
- `nix.settings`: `http-connections = 128`, `max-substitution-jobs =
  128` (parallel substitution on fat pipes) — every setting carries a
  WHY comment, a documentation style worth imitating. (GaetanLepage)
- Substituters as a data list with explicit `?priority=N` params, keys
  via `builtins.catAttrs`. (GaetanLepage)
- **`make verify-inputs` — NAR-hash guard for path/local-git flakes**
  (jwiegley `Makefile` + `bin/lib/local-git-inputs.py`) — before
  locking, check every local git input for skip-worktree /
  assume-unchanged files, uninitialized submodules, and gitlinks
  without `submodules=true`: `nix flake update` hashes the
  *filesystem* while rebuild hashes the *git archive*, so any of those
  produce activation-time NAR mismatches. Companion rule worth
  adopting as documentation even without the tool: never run `nix
  flake update` under sudo — root and user fetcher caches diverge.
- **`make travel-ready`** (jwiegley) — one target that refreshes every
  project's direnv cache and drops remote-builder dependencies before
  going offline; laptop-leaves-home as an explicit repo operation.
  There is no offline-prep story in the Makefile today.
- **Last-known-good compatibility overlay** (jwiegley
  `overlays/00-last-known-good.nix`) — one dedicated, ordered overlay
  file where every regressed package is pinned to a recorded
  known-good nixpkgs snapshot via `fetchTree`: the systematized
  version of the malob one-off pin, all regression pins in one place
  with their provenance instead of scattered workarounds.
- **Rebuild ergonomics one-liners** (EmergentMind): `nix flake update
  --timeout 5` so one dead input host doesn't hang the
  bump. Plus srid's activation-hang insurance to file away:
  `systemd.services.NetworkManager-wait-online.enable = false` and
  dbus-broker `restartIfChanged = mkForce false` are the two canonical
  "switch hangs" fixes for GUI VMs.
- **Self-registry alias** (traxys) — `nix.registry."my".flake = <this
  flake>` makes `nix run my#...` and `nix flake init -t my#<template>`
  work from any directory without a path. One line next to the existing
  `registry.nixpkgs` pin in `modules/nix-settings.nix`.
- **`pkgs-x86` Rosetta escape hatch** (malob overlays) — on
  aarch64-darwin only, expose `pkgs-x86 = import nixpkgs { system =
  "x86_64-darwin"; }` so a package broken on Apple Silicon can be
  swapped for its Rosetta build with one `inherit (final.pkgs-x86)`.
  His live example is exemplary workaround hygiene: zsh pinned from
  master with the nixpkgs issue, root cause, and fixing commit cited.
- **Task-oriented devShells on the config flake** (malob `devShells`:
  `pdf` with ghostscript/poppler/tesseract/pypdf, `docx`, a nix-dev
  shell with deadnix/statix/nixd/nixfmt) — ad-hoc toolchains per task
  rather than per project, reachable as `nix develop my#pdf` via the
  self-registry alias item above. A different niche from templates/.
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

- **Perlless activation** (parked 2026-08-29 during the closure-size
  sweep): the last ~30 MiB of perl on a server is NixOS's own activation
  scripts (setup-etc.pl, update-users-groups.pl). Removing them means
  systemd-initrd + `system.etc.overlay` + `services.userborn` (+
  `system.forbiddenDependenciesRegexes = ["perl"]` as the guard). Boot-path
  change on a remote BIOS-only VPS and it touches the sops
  `neededForUsers` password path — needs a VM boot test (Batch-C pattern)
  before nitrogen. Also parked: toolkit git → gitMinimal (would drop the
  ~10 MiB perl module env everywhere, but loses send-email/gitk/svn).

- **Unattended disk encryption via TPM2** (lovesegfault
  `configurations/nixos/hegel/tpm-decrypt.nix`; the manual sibling is
  eh8's `remote-unlock.nix` initrd sshd) — a small LUKS credstore
  holds the data key, TPM2-sealed to PCR 7 (Secure Boot) *plus* PCR 15
  with `tpm2-measure-pcr=yes` so the key unseals only during initrd
  and never on the running system (credits oddlama's attack writeup).
  ~600 lines with re-enrollment and troubleshooting runbooks — the
  best-documented answer to the STIG no-disk-encryption finding for
  hosts that must reboot unattended; eh8's ssh-with-forced-command
  initrd is the option where a human unlock is acceptable.
- **BBR + cake on the internet path** (lovesegfault
  `fast-networking.nix`) — `net.core.default_qdisc = "cake"`,
  `net.ipv4.tcp_congestion_control = "bbr"`, plus `tcp_mtu_probing`,
  rfc1337, and conntrack/buffer sizing. Candidate for nitrogen.
- **SMART health monitoring** (heywoodlh `nixos/modules/scrutiny.nix`;
  LongerHV's `services.prometheus.exporters.smartctl` is the
  exporter-only variant) — disk-failure early warning for helium, the
  fleet's one stateful machine; a monitoring category nothing else
  filed covers.
- **`networking.nftables.stopRuleset`** (oddlama `config/nftables.nix`)
  — a minimal drop-policy ruleset (established/related + ssh port +
  icmp only) that NixOS installs whenever the nftables unit stops or
  fails mid-reload: the firewall can never end up open, and the host
  can never end up unreachable, during a bad switch. Upstream option,
  ~2 dozen lines; take verbatim for nitrogen's bogons/firewall setup.
- **Outbound mail on every host** (xddxdd
  `nixos/minimal-components/smtp.nix`) — fleet-wide `programs.msmtp`
  with a sops-stored relay password so cron/systemd/backup failures
  can actually send email. An ops category the servers lack entirely;
  pairs with barrucadu's `$SERVICE_RESULT` alerting in Backup and DR.
- **phone-push** (chvp `modules/base/phone-push/default.nix`) — a
  10-line script on every host: `curl $(cat $SECRET_URL) -d
  "$(hostname): $@"`, with the push endpoint URL kept as a secret (a
  secret ntfy-style topic URL is the auth). The cheapest
  server-wants-attention primitive; the push counterpart of the msmtp
  item above.
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
- **inotify watch bump for dev VMs** (dustinlyons):
  `boot.kernel.sysctl."fs.inotify.max_user_watches" = 1048576` — stops
  file-watcher exhaustion with big repos under editors/direnv in the VM.
- **systemd-oomd on the dev VM** (traxys) — his `gui/nixos.nix` enables
  `systemd.oomd` with user/root/system slices. A big `nix build` inside the
  VM OOM-freezing the guest is exactly the failure mode this catches.
  Self-contained addition to `modules/vm.nix`.
- **VM/host one-liners** (Mic92, machines/, nixosModules/):
  `services.getty.autologinUser` on the throwaway VM;
  `services.dbus.implementation = "broker"`.
- **Slim the closure** (drupol) — `environment.defaultPackages =
  lib.mkForce [ ]` (drops nano/perl/rsync/strace);
  `documentation.*.enable = false` for headless (measurable eval win).
  (`command-not-found` checked 2026-08-26: already off everywhere — the
  NixOS default follows `nix.channel.enable`, which the repo disables,
  and the HM option defaults off. Nothing declared; Michel's call.)
- **Server closure one-liners, second batch** (Weathercold
  `nixos/modules/profiles/server.nix`) — `fonts.fontconfig.enable =
  false` on headless hosts; and declare `time.timeZone = "UTC"`
  explicitly so the convention is enforced, not assumed.
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
- **Derive service enables from the filesystem table** (hoenn
  `nix/modules/nixos/services/scrubs.nix`) — `services.btrfs.autoScrub.enable
  = lib.any (fs: fs.fsType == "btrfs") (lib.attrValues config.fileSystems)`.
  One line, no per-host toggle to forget on the next machine. Same trick for
  fstrim, zfs scrub and smartd.
- **`systemd.enableEmergencyMode = false` on headless hosts** (sinnoh
  `nix/nixos/systemd.nix`) — on a box with no console, emergency mode is a
  machine that hangs forever at a root-password prompt instead of continuing
  to boot. Same module also sets `coredump.enable = false` and turns
  `systemd.oomd` on for the root, system and user slices. Three lines,
  straightforwardly right for the VMs and the VPS.

## Terminal: ghostty, tmux, less

- **bash port of zsh-done** (follow-up to the vendored `.zsh_done`). The
  fleet's interactive shell is bash
  (`users/mich/nixos.nix` sets `shell = pkgs.bash`), so the ssh-into-fleet
  case needs a bash version: vendor `rcaloras/bash-preexec` (single file,
  synthesizes preexec/precmd from the DEBUG trap + PROMPT_COMMAND; what
  iTerm2/Atuin build on, coexists with direnv) plus a ~40-line port of the
  done logic sharing the `DONE_*` variables and calling `osc777.sh`. The
  tmux active-pane suppression is plain ps/tmux and ports over too.
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
- **`LESSUTFCHARDEF` for Nerd Font icons** (malob) —
  `"E000-F8FF:p,F0000-FFFFD:p,100000-10FFFD:p"`: less 632+ hides PUA
  characters by default, so icons vanish in less/bat without it.
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

- **Post-quantum ssh crypto pinning** (reckenrode
  `modules/by-name/op/openssh/nixos-module.nix` + xddxdd
  `nixos/minimal-components/ssh-harden.nix` — two independent
  sightings) — sshd `KexAlgorithms
  mlkem768x25519-sha256,sntrup761x25519-sha512` first, ed25519-only
  host/pubkey algorithms, etm-only MACs / aes256-gcm. OpenSSH ≥9.9
  ships mlkem. Nothing pins crypto algorithms here today; fits the
  Anduril-STIG thread for nitrogen's internet-facing sshd.
- **ssh over WebSocket on 443** (kurnevsky `modules/websocat-ssh.nix`
  + `modules/server/websocat-ssh-server.nix`) — server side: a ~15-line
  DynamicUser unit bridging `wss://host/wssh` to `127.0.0.1:22` behind
  an nginx `proxyWebsockets` location; client side: the mirror unit
  exposing a local port. Reaches nitrogen from networks where only
  443/TLS passes — the principled version of the port-3333 workaround.
  Same repo has a `websocat-wg` pair for WireGuard, plus `iodine.nix`
  (DNS tunnel) and `hans.nix` (ICMP tunnel) as further fallbacks.
- **Forge host-key pinning** (josephst
  `hosts/common/ssh-infrastructure.nix`) — `programs.ssh.knownHosts`
  carries the github.com/gitlab.com ed25519 keys declaratively, so
  fresh hosts never TOFU the forges. Small delta on the filed fleet
  knownHosts item.
- **`IPQoS none`** (Kidsan) — disables DSCP marking on ssh packets;
  the known fix when ssh stalls behind QoS-mangling routers or VPNs.
- **`StreamLocalBindUnlink = "yes"` in sshd** (drupol) — server removes
  stale forwarded unix sockets, the fix for agent/gpg socket forwarding
  breaking on reconnect. Direct fit for the ssh-into-VM workflow.
- **mDNS fleet names** (mightyiam) — avahi with `nssmdns4 = true`, fleet
  knownHosts on `<host>.local` names: no DHCP-address tracking for the
  Fusion/UTM VMs.
- **sudo NOPASSWD → agent-authenticated** (follow-up to pam_rssh).
  pam_rssh is wired into the sudo PAM stack on vm + server
  (accounts.nix), but `wheelNeedsPassword = false` means sudo skips PAM
  entirely, so it is inert. The real posture change is flipping that to
  true: sudo then authenticates against the forwarded agent (sufficient),
  falling back to mich's password. Agent forwarding to the fleet hosts
  is already configured (fleet match block in programs.ssh); a decision
  on whether the GCE image keeps NOPASSWD (OS Login admins have their own
  sudoers path). sebastianrasor goes further — `sudo.unixAuth = false`,
  agent-only; decided against for now (console lockout risk).
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
- **jj for the GitHub PR flow** (mrcjkb
  `home-manager-base/programs/jujutsu.nix`; gvolpe agrees on
  signing.behavior) — `templates.git_push_bookmark = "\"mo/push-\" ++
  change_id.short()"` (deterministic push-bookmark names, the missing
  piece for jj-with-PRs), `templates.commit_trailers =
  format_signed_off_by_trailer(self)`, `signing.behavior = "own"`
  (sign only your own commits — middle ground between always-sign and
  the sign-on-push item above), `fsmonitor.watchman
  .register-snapshot-trigger = true`, and branch-relative log aliases
  (`l = (main..@):: | (main..@)-`).
- **gitconfig stragglers, round two** (jtojnar + mrcjkb) —
  `core.fsmonitor = true` (builtin FS-monitor daemon; big-repo status
  speedup), `core.commentChar = ";"` (frees `#` so markdown headings
  survive in commit messages), `push.followTags = true` (annotated
  tags ride along).
- **jj working-copy guards** (enocla) — `fsmonitor.backend = "watchman"`
  (fast snapshots in big repos; needs the watchman package) and
  `snapshot.max-new-file-size = "10MiB"` (jj refuses to auto-snapshot a
  stray tarball instead of baking it into history).
- **thoughtpolice jj revset library** (astratagem/dotfield
  `src/features/jujutsu/revset-aliases.nix`, from the thoughtpolice
  gist; absorbs the shikanime-labs aliases filed 2026-09-02) —
  `stack(x, n)` = `ancestors(reachable(x, mutable()), n)`; `open()` =
  all stacks reachable from `@` or `mine()`; `ready()` = `open()` minus
  descendants of a `blacklist()` matching `wip:`/`private:` description
  prefixes; `mine()` OR-ing all the user's email identities; plus
  shikanime's `prune` = abandon `empty() & mutable() & conflicts()`.
  Companion aliases: `harvest`/`eject` (squash into/out of `@`),
  `cat` = `file show`, `credit` = `file annotate`. The complete
  what's-in-flight/what's-submittable workflow, richer than the
  drupol/vic library above.
- **`diff.colorMoved = "default"`** (enocla) — moved code rendered
  distinctly in git diffs; rides along with the batch-A7 gitconfig set.
- **gitconfig stragglers, September sweep** (marcusramberg + shuntaka) —
  `log.follow = true` (follow renames in `git log <file>`),
  `fetch.all = true`, `submodule.recurse = true`, `core.whitespace =
  "trailing-space,space-before-tab"`; shuntaka's `rbsync` alias
  (dirty-tree-guarded `fetch --prune` + rebase onto `@{upstream}`,
  falling back to auto-detected `origin/HEAD`).
- **Declarative gh extensions** (marcusramberg `home/git.nix`) —
  `programs.gh.extensions = [ gh-poi gh-notify gh-dash ... ]` pins the
  extension set instead of `gh extension install` drift; gh-poi (delete
  local branches whose PRs merged) and gh-notify (notifications in the
  terminal) are the two worth starting with.
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

- **Completion zstyles worth lifting wholesale**
  (ambroisie `completion-styles.zsh`) — `menu select`, LS_COLORS in
  completion listings, `group-name`, `squeeze-slashes`, colored `kill`
  completion from verbose `ps`, case-insensitive `matcher-list`,
  per-category `format` strings.
- **zsh options** (ambroisie `options.zsh`) — `inc_append_history_time`
  (instead of share_history), `hist_reduce_blanks`, `hist_verify`,
  `rc_quotes`, `auto_pushd pushd_minus pushd_silent`, `auto_resume`
  (bare `vim` resumes the stopped job).
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
- **Centralized direnv layout dirs** (lovesegfault
  `modules/home/dev/default.nix` `programs.direnv.stdlib`) —
  `direnv_layout_dir` hashes `$PWD` into
  `$XDG_CACHE_HOME/direnv/layouts/`: no `.direnv/` litter in any
  repo, and one GC-able cache.
- **direnv `~/src` whitelist** (clo4 + berbiche) —
  `whitelist.prefix = [ "~/src" ]` skips
  the `direnv allow` ritual for own checkouts, but auto-executes any
  `.envrc` under it. Pending decision: do third-party clones ever land
  in `~/src`?
- **Completion cache keyed on binary mtime** (franckrasolo
  `home/zsh/completions.cache.zsh`) — `_cache_completion` regenerates
  `<tool> completion zsh` output only when the binary is newer than the
  cached copy, else sources the cache. Targets the completion cost
  listed as a remaining hotspot in the zsh-startup profiling notes.
- **Custom direnv stdlib helpers** (ambroisie `modules/home/direnv/lib/`)
  — extra `use …` functions (nix_shell, postgres, python) shipped via
  home-manager next to the existing offline-aware stdlib.
- `use_nix_installables() { direnv_load nix shell "$@" -c $direnv dump; }`
  — ad-hoc per-project toolsets without writing a devshell. (vic)

## macOS / darwin

- **Hosts-file blocklist module** (DavSanchez
  `modules/darwin/stevenblack.nix`) — `networking.hostFiles` from the
  packaged StevenBlack list with category extensions and a
  regex-validated whitelist applied at build time. Ad/malware blocking
  on neon itself, no daemons; complements the blocky-for-helium
  package candidate.
- **Application-firewall allowlist reconciliation** (heywoodlh
  `base/sshd.nix` postActivation) — `socketfilterfw --listapps` grepped
  for stale `/nix/store/*/bin/<listener>` entries, old paths
  `--remove`d, the current one `--add`ed/`--unblockapp`ed on each
  activation. Store paths churn every rebuild, so the per-binary
  allowlist of the firewall enabled for the ERNW audit silently goes
  stale for any nix-installed listener; this is the fix.
- **Commands as launchable apps** (heywoodlh
  `home/modules/applications.nix` `createApp`) — render any shell
  command into a minimal real `.app` bundle (Info.plist + icns) on
  darwin or a `.desktop` file on Linux, so nix-defined commands are
  Spotlight/launcher-visible. Complements mac-app-util, which only
  handles existing bundles.
- **Location-aware screen lock** (self-originated 2026-09-24; Michel wants a
  relaxed lock at home and a strict one away). The mechanism is settled by
  measurement, the choices are not.

  What is ruled out: varying the *delay* by location.
  `sysadminctl -screenLock <seconds> -password <pw>` requires the account
  password, so no background agent can flip it without storing the password,
  and nix-darwin's `system.defaults.screensaver.askForPassword` /
  `askForPasswordDelay` write keys macOS 27 ignores (see the note in
  `modules/workarounds.nix`). `CGSession -suspend`, the classic lock command,
  no longer exists on 27.

  What works: keep one grace period and **lock on the transition**. Leaving
  the home network is the moment the laptop goes in the bag, and triggering a
  lock needs no authentication. A nix-darwin `launchd.user.agents` unit woken
  by `KeepAlive.NetworkState` or a `scutil -w State:/Network/Global/IPv4`
  loop, comparing the current network against "home" — about 30 lines.

  Decision 1, home detection (weakest to strongest): SSID — trivially
  spoofed, anyone can name an AP the same thing; **default-gateway MAC** —
  spoofable but requires knowing it, keep the value in sops rather than this
  public repo, instant, and its failure mode is a needless lock, which is the
  safe direction; a **fleet host's SSH host-key fingerprint** via
  `ssh-keyscan` on the LAN address — unspoofable without that host's private
  key (host keys are already the sops age identities), but costs seconds and
  needs the host up. Leaning gateway MAC here, keeping the host-key check for
  the day something more valuable than a lock delay is relaxed by location.

  Decision 2, the lock call: `hammerspoon` is *not* in nixpkgs (checked
  aarch64-darwin; `sleepwatcher` is), so it would come from `homebrew.casks`
  with the Lua config as a `home.file` — still declarative, and
  `hs.caffeinate.lockScreen()` locks immediately and leaves somewhere to hang
  further location rules. Without it, `osascript` sending Cmd-Ctrl-Q works but
  needs an Accessibility grant for the agent, and `pmset displaysleepnow` only
  sleeps the display, so the lock still waits out the grace period.

- **Firewall + loginwindow hardening** (malob `darwin/general.nix` +
  `darwin/defaults.nix`; tjmaynes agrees on the loginwindow pair) —
  `networking.applicationFirewall.enableStealthMode = true` (drop
  ICMP/probe responses; one line on top of the firewall enabled for
  the ERNW audit), `system.defaults.loginwindow.GuestEnabled = false`,
  `loginwindow.DisableConsoleAccess = true`.
- **prefmanager** (malob's own tool, flake input) — watches macOS
  `defaults` domains live so the key behind any GUI toggle can be
  discovered; the tool for the remaining audit leftovers (AirPlay
  receiver et al.) and a natural companion to the symbolic-hotkeys
  item above.
- **Per-user defaults via HM `targets.darwin.defaults`** (reckenrode
  `modules/by-name/de/defaults/`) — write arbitrary defaults domains
  at HM activation instead of system activation, including domains
  nix-darwin has no options for: declarative **Safari** hardening
  (`AutoOpenSafeDownloads = false`, AutoFill toggles, search
  provider). Travels to any HM-only host.
- **Keyboard-AI killers + F-keys** (reckenrode; fnState also jwiegley)
  — `NSAutomaticInlinePredictionEnabled`,
  `NSAutomaticTextCompletionEnabled`,
  `WebAutomaticSpellingCorrectionEnabled` all false (completes the
  substitution-killer block in darwin.nix), `"com.apple.keyboard
  .fnState" = 1` (F1–F12 as function keys), `"com.apple.sound.beep
  .feedback" = 0`, `screencapture.type = "png"`.
- **Unfree as an explicit allowlist** (reckenrode) —
  `allowUnfreePredicate = pkg: elem (getName pkg) [ ... ]` instead of
  neon's blanket `allowUnfree = true`: every unfree package is named.
  Cheap posture win matching the audit mindset.
- **Log paths for the linux-builder** (thiagokokada
  `modules/nix-darwin/nix/linux-builder.nix`) —
  `launchd.daemons.linux-builder.serviceConfig.StandardOutPath/
  StandardErrorPath = "/var/log/darwin-builder.log"`: two lines; the
  builder currently logs nowhere and debugging means `sudo ssh
  linux-builder`.
- **Remote NixOS host as the Mac's builder, declaratively**
  (reckenrode `hosts/josette/configuration.nix`) — `nix.buildMachines`
  with inline base64 `publicHostKey` (no TOFU), `protocol = "ssh-ng"`,
  plus an `/etc/ssh/ssh_config.d/` Match-block drop-in for the builder
  user/agent/port. The wiring pattern if neon ever uses helium as a
  builder beside the local VM.
- **macOS/darwin one-liners** (vic) — `ApplePressAndHoldEnabled = false`;
  darwin tooling installed from the pinned nix-darwin input; `nix.gc`
  wrapped in `optionalAttrs config.nix.enable` so modules eval on
  Determinate-managed Macs.
- **Declarative macOS symbolic hotkeys, applied live** (franckrasolo
  `darwin/macOS/keyboard.nix`; jdheyburn independently via
  `CustomUserPreferences."com.apple.symbolichotkeys"`) — write
  `AppleSymbolicHotKeys` dicts (60/61 = input-source switch, 64 =
  Spotlight Cmd+Space, Mission Control grabs), then apply without
  logout via the private `activateSettings -u` binary
  (SystemAdministration.framework). Same activation script disables
  Terminal's "Open man Page" Services via `defaults write pbs
  NSServicesStatus`; jdheyburn adds `NSUserKeyEquivalents` to
  neutralize per-menu-item shortcuts (accidental Cmd+M). The nix path
  to the "GUI toggle" class of audit leftovers.
- **Control Center menu-bar items via ByHost plist** (franckrasolo
  `darwin/macOS/menubar.nix`) — `CustomUserPreferences` on the ByHost
  path (`~/Library/Preferences/ByHost/com.apple.controlcenter.plist`),
  8 = hide / 9 = show per module, plus hiding the Spotlight menu icon.
  Transferable bit: some defaults domains only take effect per-host.
- **macOS defaults odds, September sweep** (franckrasolo, clo4,
  jdheyburn) — `universalaccess.reduceMotion = true`;
  `NSGlobalDomain."com.apple.sound.beep.volume"` (+ `.sound` in
  `".GlobalPreferences"`); `dock.autohide-delay = 0.0` +
  `autohide-time-modifier = 0.0`; `NSGlobalDomain
  .NSWindowShouldDragOnGesture = true` (ctrl+cmd-drag any window from
  anywhere); global-domain `AppleShowAllExtensions` (the finder-domain
  one here doesn't cover save dialogs); `menuExtraClock.ShowDate` /
  `ShowDayOfWeek`; `CustomUserPreferences."com.apple.TextEdit"
  .RichText = 0`.
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
- **GitHub App token instead of a PAT** (shikanime-labs
  `actions/create-github-app-token` + a repo-scoped "operator" App) —
  the stronger variant of the two PAT items above: App-minted tokens
  trigger required checks on pushed PRs, don't expire, and scope to the
  repo instead of the account. Prefer this when fixing update-lock.
- **nvfetcher for non-flake source tracking** (shuntaka9576
  `nvfetcher.toml` + `_sources/generated.nix` + a daily workflow) —
  upstream sources that shouldn't be flake inputs (Go tools built from
  source, `anthropics/skills`) declared in one TOML, materialized as
  `pkgs.sources.*` via overlay (`buildGoModule { inherit
  (pkgs.sources.pet) pname version src; }`); the cron opens a PR
  touching only the generated file. Upstream trackers bump on their own
  cadence with zero flake.lock churn — the lock-free counterpart to the
  skills-as-flake-inputs item.
- **CI builds the real darwin config** (malob `githubCI` +
  `.github/workflows/ci.yml`) — the laptop config with identity
  overridden and homebrew/`/etc/shells` mkForce'd off builds on a
  `macos-latest` runner and pushes to cachix. Noted as the pattern to
  reach for only if the 2026-08-23 eval-only-neon CI decision is ever
  revisited; the makeOverridable identity item (§4) is what makes it
  cheap. Operational detail (DavSanchez
  `hosts/darwin/ci/linux-builder-bootstrap.nix`): QEMU aborts instead
  of falling back when HVF init fails on Actions runners, so the
  linux-builder needs a wrapper rewriting `accel=hvf:tcg` to
  `accel=tcg` there.
- **Workflows generated from nix** (thiagokokada `actions/*.nix` →
  committed YAML via `nix eval`) — job steps and host lists derive
  from the flake's own `nixosConfigurations`/`darwinConfigurations`
  attrs, so adding a host adds its CI step; a `validate-flakes` job
  guards staleness. Distinct from the vic runtime-matrix item: the
  whole workflow file is generated, committed, and diffable.
- **Two-stage lock-bump CI** (thiagokokada `actions/update-flakes.nix`
  + `-after.nix`) — the scheduled bump builds cheap x86_64-linux and
  opens the PR; a `workflow_run`-triggered second stage builds
  darwin/aarch64 only if stage one passed. Expensive runners never
  chew on a broken bump.
- **flat-flake lock hygiene check** (xddxdd's own tool, flake input) —
  CI assertion that flake.lock holds no duplicated transitive inputs,
  i.e. every `follows` is actually wired. One check target; fits the
  "a lock refresh is a real version bump" discipline.
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
- **Render the whole GitOps tree and schema-check it in CI** (devon-systems/sinnoh
  and johto, `scripts/check-k8s.py` + `nix/check-k8s.nix`, ~80 lines of Python)
  — walk the Flux Kustomization graph breadth-first from `k8s/flux-system`,
  `kustomize build` each directory, follow every
  `kustomize.toolkit.fluxcd.io` resource's `spec.path` to the next one,
  `helm template` the HelmReleases whose chart is a local `GitRepository`,
  drop documents containing `sops` (CI holds no keys, and some documents
  encrypt even `kind`), then `kubeconform -strict` the lot against a *pinned*
  datreeio CRDs-catalog commit and a pinned Kubernetes version. Both a
  `spec.path` and a chart path outside the repo root raise rather than
  render. Shipped as `pkgs.writeShellApplication` with kustomize, helm and
  kubeconform in `runtimeInputs`, so `nix run .#check-k8s` is the whole CI
  step. The best single idea in either repo, and the shape ports to any
  manifest tree: render everything reachable, then validate.

## GCE roadmap (self-originated)

- **Launch-verify gVNIC**: after the next `gce/upload`, boot an instance
  with `--network-interface nic-type=GVNIC` and confirm the NIC is eth0
  with the gve driver bound and a DHCP lease.

---

# 3. Secrets: decided and implemented (2026-08-27) — queue now open

**Decided 2026-08-27: sops-nix.** Host SSH keys are the age identities
(Misterio77 pattern), Michel's Secure Enclave key (age-plugin-se, Touch
ID) is the editing identity, and every file under secrets/ is guarded by
an eval test that fails CI on plaintext. Canary secret verified
end-to-end on nitrogen. Recovery recipients (2026-08-28): both YubiKeys
(Security Key C NFC, so age-plugin-fido2-hmac, not the PIV plugin) are
enrolled with PIN-gated separate identities — the identity files in
keys/ are salt+credential-id only, safe in the public repo; recovery =
repo + physical key + FIDO2 PIN, both keys decrypt-tested. A FIDO2 reset
of either YubiKey permanently invalidates its credential.

The "Unblocked once decided" list below is now an actionable queue. (The
alternatives considered — agenix variants, TPM-sealed keys, git-crypt,
private-repo-as-input, Bitwarden passwordCommand — were removed in the
2026-09-06 cleanup; git history has them.)

## Unblocked queue (decision made — pick and implement)

- **Tailscale auto-join for turnkey substrates** (reshaped 2026-09-05
  from "auto-join on first boot"). No custom boot service: upstream
  `services.tailscale.authKeyFile` already ships a tailscaled-autoconnect
  oneshot that runs `tailscale up` once when the node is logged out;
  `extraUpFlags` carries the rest. Key material is a tag-scoped OAuth
  client secret (`tskey-client-...`, accepted by authKeyFile with
  `--advertise-tags`), not a plain auth key — those expire within 90
  days and would rot in sops. Scope: an opt-in `tailscale-autojoin`
  feature module composed only into substrates deployed turnkey — the
  GCE image first (secret from instance metadata / Secret Manager;
  sops can't ride a template image, per-instance host keys don't exist
  at build time), with ephemeral+preauthorized keys so cattle
  self-clean per the 2026-08-25 role split. NOT on base or the pets:
  their tailscaled state persists across rebuilds, so auto-join only
  helps at reinstall while parking a join-capable secret on every host
  (blast radius: a compromised host could mint tagged nodes).
  Prerequisite: create the OAuth client with the right tag scope in
  the admin console. See also the `--encrypt-state=false` imaging note
  in the GCP section.
- **Home-manager-level sops** (astratagem/dotfield
  `src/features/secrets/default.nix`) — a second sops-nix layer inside
  HM decrypting with the *user's* ssh key (`sops.age.sshKeyPaths` on
  the home side): user-owned secrets with no root/system involvement.
  Relevant for user-scoped tokens, and the only sops path on
  foreign-Linux HM-only hosts (the helium homeConfigurations idea)
  where system sops doesn't exist.
- **sops key-rotation targets** (CnTeng `Makefile`) — `update-keys` =
  `fd secrets.yaml --exec sops updatekeys --yes` (re-wrap after a
  recipient change), `rotate-keys` = `sops rotate -i` (new data key
  per file). The rotation story the sops setup here lacks; two
  Makefile lines.
- **Runtime secret injection via wrapper** (malob `home/packages.nix`
  `mkOpRunWrapper`) — wrap a tool so its token becomes an env var only
  at exec time (his: `op run` for nix-update/nixpkgs-review GitHub
  tokens), built with `symlinkJoin` so completions and man pages from
  the original package survive. Ports to sops-fed secrets; the
  never-touches-disk-or-store pattern for tool credentials.
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
- **Generate `.sops.yaml` from `keys/*.pub`** (hoenn `.justfile`,
  `sops-rekey` + `sops-bootstrap`) — one recipe converts every committed ssh
  pubkey to an age recipient with `ssh-to-age`, rewrites `.sops.yaml` (with a
  generated-by header and YAML anchors per host), then walks `secrets/**` and
  runs `sops updatekeys -y` on each file whose `sops filestatus` reports it
  encrypted. Adding or removing a machine becomes "drop a `.pub` in `keys/`,
  re-run the recipe". Companion `sops-bootstrap` derives the machine's age
  private key from its existing `~/.ssh/id_ed25519` and installs it at
  `~/.config/sops/age/keys.txt`, idempotently. Supersedes the narrower CnTeng
  `update-keys` item above: same `updatekeys` call, but the recipient list is
  generated rather than hand-maintained.
- **Fail on an encrypted file nothing references** (derived from the
  `johto/secrets/kubernetes/` wart, 2026-09-15) — johto carries a directory of
  live, correctly-encrypted secrets for services that moved to another
  cluster: nothing imports it, no kustomization lists it, `.sops.yaml` still
  re-keys it on every recipient change, and so credentials that should have
  been revoked stay current indefinitely. A rekey recipe that walks
  `secrets/**` preserves exactly the material that most needs rotating, and
  makes it look maintained. The guardrail belongs beside the existing
  plaintext eval test: for each file under `secrets/`, assert some module or
  manifest names it, and fail the check otherwise. Deleting a stale secret is
  not enough on its own — a file that reaches this state has been decryptable
  by every recipient for however long it sat there, so the finding is "rotate,
  then delete". Prerequisite for adopting the generated-`.sops.yaml` recipe
  above, not a follow-up to it.
- **`sops.templates` with `restartUnits`, worked example** (johto
  `nix/hosts/nixos/goldenrod/garage.nix`) — the whole garage TOML config is a
  `sops.templates` entry owned by the service user at mode 0400 with the RPC
  secret interpolated through `config.sops.placeholder.<name>`, plus a second
  template rendering an EnvironmentFile; `restartUnits = ["garage.service"]`
  makes a secret change restart the consumer. Second sighting of
  `sops.templates` (after eh8) and the first complete example: this is the
  answer whenever a service wants one config file containing both settings and
  a secret, instead of a secret path it can read.

---

# 4. Projects and real decisions

## Backup and DR — first priority (2026-08-25 fleet discussion)

- **Cold-standby via a flag file** (zentralwerk/network
  `server/lxc-containers.nix`): both servers carry identical config for
  every workload; `lxc@` units gate on `ConditionPathExists =
  /etc/start-containers`, so which box is live is one touch/rm, and
  failover is "run enable-containers on the spare". Their workload units
  also set `restartIfChanged = false` so a host rebuild never bounces the
  services. Cheap DR shape for the helium/nitrogen role split once
  services multiply — the config is always deployed everywhere, only the
  activation flag moves.

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
- **Time Machine target on a NixOS server** (totoroot
  `modules/services/time-machine.nix`) — Samba with the `fruit:aapl` /
  `catia fruit streams_xattr` VFS stack plus Avahi `_adisk` records
  (netatalk deliberately retired, nmbd off to dodge crashes), shares as
  typed submodules. Would let neon back up to helium over the LAN
  declaratively — a direct answer to the macOS-audit backup TODO.
- **Option-gated backup module shape** (eh8 `modules/nixos/kopia-backup.nix`)
  — per-host `paths` list option; non-empty wires a sops repository
  token, a oneshot `connect → snapshot → disconnect` service, and a 4am
  randomized timer, ~40 lines. Same shape works with the restic already
  in `home.packages` (or `services.restic.backups`); combines with the
  ambroisie baseline-path-list item above.
- **vorta cask** (mrkuz) — borg-backup GUI with a committed
  default-profile JSON, if the neon side wants a GUI instead of
  Time Machine.
- **Dead-man's-switch for backup jobs** (jdheyburn
  `modules/nixos/backup/usb.nix`) — self-hosted `services.healthchecks`
  + restic `backupPrepareCommand` curling `/ping/<uuid>/start` and
  `backupCleanupCommand` curling `/ping/<uuid>/$status`, extracting the
  real `ExecStartPre` exit status via `systemctl show -p ExecStartPre`
  so a failed pre-command isn't reported as success. The monitoring
  half missing from the module shapes above: a backup that silently
  stops running gets noticed. Cleaner mechanism (josephst
  `modules/nixos/healthchecks.nix`): a module that gives any systemd
  unit start/success/fail ping services, with the URL delivered via
  `LoadCredential` so it never appears in the unit environment.
- **Offsite copy as unit ordering** (jdheyburn, same file) — an
  `rclone`-to-B2 service with `wantedBy`/`after =
  [ "restic-backups-<name>.service" ]`: local snapshot then offsite as
  systemd dependency, no cron choreography. Candidate mechanism for
  the helium offsite item in §4.
- **encrypt_if_changed + deterministic tar** (dustinlyons
  `modules/nixos/backups.nix`) — age output is randomized per run, so
  the script hashes the *plaintext* (`<file>.age.sha256` beside the
  ciphertext) and skips re-encryption when unchanged; archives built
  with `--sort=name --owner=0 --group=0 --numeric-owner --mtime=@0` so
  they're byte-comparable. Useful wherever change detection gates an
  encrypted or archived artifact.
- **rrsync-confined backup receivers** (jtojnar azazel backup wiring)
  — OpenSSH's restricted-rsync as the forced command on the backup ssh
  key, so the receiving end can only rsync into one directory.
  Receiver-side key confinement, composing with every backup shape
  here.
- **Restic hardening + verification trio** (barrucadu
  `shared/restic-backups/default.nix`) — backups run as an
  unprivileged `backups` user with `AmbientCapabilities =
  "CAP_DAC_READ_SEARCH"` (read everything, root nowhere) and
  narrowly-scoped per-backup NOPASSWD dump sudoRules; a scheduled
  `restic check` service verifies repository *integrity* (the third
  leg after "take snapshots" and jdheyburn's "did it run"); `postStop`
  + `$SERVICE_RESULT` alerts on any non-success with no monitoring
  stack needed.
- **Restore procedure as a flake app** (barrucadu `scripts/backups.sh`)
  — `nix run .#backups -- snapshots/restore` versions the operator
  tooling beside the backup config; restores land in
  `/tmp/restic-restore-<snapshot>` by default. Recovery stops being
  tribal knowledge.
- **External monitors reconciled from repo data** (xddxdd
  `tools/sync-uptimerobot-monitors.py`) — create/patch/delete
  UptimeRobot (free tier) monitors via API to match the nix host
  registry: the externally-hosted dead-man's-switch complement to the
  self-hosted healthchecks item above.
- **Boot-generation pinning** (EmergentMind): `just pin` copies the current
  systemd-boot entry to `hosts/<n>/pinned-boot-entry.conf` (title
  "PINNED:"), registers a GC root for that generation, and the module
  re-injects it via `boot.loader.systemd-boot.extraEntries` guarded by
  `lib.pathExists`. A known-good generation that survives both GC and
  `configurationLimit` — nice safety rail for the VMs, portable to a `make
  pin` target.
- **`backupPrepareCommand` as a precondition assertion** (hoenn
  `nix/hosts/nixos/mauville/backups.nix`) — before the ROMs backup runs,
  `set -eu; mountpoint -q /mnt/Storage; test -d <path>`. A failed assertion
  fails the unit, so restic never snapshots an empty mountpoint and then
  prunes the real data out of the repository on the retention pass. That is
  the backup failure that stays silent until a restore. Cheap to add to every
  path-based backup job; pairs with the dead-man's-switch item.
- **Make the artifact you are about to back up** (sinnoh
  `nix/hosts/nixos/sunnyshore/k3s.nix`) — `backupPrepareCommand =
  "${config.services.k3s.package}/bin/k3s etcd-snapshot save"`, with `paths`
  pointing at the snapshots dir plus `server/cred` and `server/tls`. One unit
  takes a fresh etcd snapshot and ships it, so there is no separate timer to
  drift out of step. The companion half is the other restic job excluding the
  CNPG PVC (`--exclude=.../*_cnpg-system_pg-shared-1/**`): postgres is backed
  up exactly once, by the tool that can do it consistently, not twice and
  torn. Generalises: exclude from the filesystem backup anything that has its
  own consistent backup.
- **Postgres backups as a CNPG plugin to object storage** (sinnoh/johto
  `k8s/postgres-backups/object-store.yaml`, `k8s/postgres/scheduled-backup.yaml`)
  — the `barman-cloud` plugin as `isWALArchiver`, a `ScheduledBackup` at
  04:00, `retentionPolicy: 30d`, destination a B2 bucket over the S3 API with
  credentials from a sops-encrypted secret. Continuous WAL archiving plus
  daily base backups, declared in about 40 lines of YAML. The reference shape
  if postgres ever lands on helium.

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
- **`users.primaryUser` typed option + overridable host template**
  (malob `modules/darwin/users.nix` + `lib/mkDarwinSystem.nix`) — the
  stronger sibling of the specialArg item above: identity (username,
  fullName, email, nixConfigDirectory) as a typed option set injected
  into both the darwin config and HM (`home.user-info`), with the host
  wrapped in `lib.makeOverridable` so variants are one `.override`
  (his `githubCI` = same laptop config, runner identity, homebrew
  mkForce'd off). The concrete implementation of the fleet-axes
  identity axis and singleton→template conversion.
- **homeConfigurations for foreign-Linux hosts** (malob + madmaxieee
  independently) — a standalone `homeConfigurations.<host>` output run
  with `home-manager switch --flake` on machines whose OS isn't ours;
  the two settings that make it work on a foreign distro are
  `nix.package = pkgs.nix` (so `nix.settings` applies without a system
  module) and `TERMINFO_DIRS` pointing at the HM profile. The path to
  bringing helium (Debian, drifting from the repo) under repo
  management without an OS conversion; pairs with the HM-level sops
  item in §3.
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

- **Bootstrap darwin configurations** (malob `darwinConfigurations
  .bootstrap-arm`) — a minimal config as a first-activation target on a
  fresh Mac. Our equivalent gotcha (first activation must use the
  un-customized linux-builder or it cache-misses) lives as prose in
  neon.nix; a bootstrap target would encode it as something runnable.
- **Tailnet policy and DNS as Terraform in the config repo**
  (foo-dogsquared `terraform/tailscale.tf`, `terraform/dns.tf`) — the
  tailscale ACL (`tagOwners`, groups, ssh rules, `autoApprovers`) and
  public DNS records as resources beside the fleet config. Extends the
  shikanime GitHub-settings-in-Terraform item to the two control
  planes this fleet actually depends on; the §3 exit-node
  `autoApprovers` plan assumes console clicking today. DNS caveat:
  needs a TransIP provider. CnTeng's `infra/` adds two planes:
  Cloudflare R2 buckets, and least-privilege API tokens minted as
  `cloudflare_api_token` resources — service credentials themselves
  declarative.
- **Self-fencing risky deploys** (zentralwerk/network switch templates):
  every remote change that can cut off access arms an automatic revert
  *before* applying — Junos `commit confirmed 5` (second ssh confirms;
  if it never lands the switch rolls itself back), Cisco `reload in 5` +
  probe + `reload cancel`. Same shape as the bootctl
  set-default/set-oneshot pattern proven on the fusion VM 2026-08-29;
  steal for anything remote where a bad config means a console trip
  (nitrogen firewall/network changes).

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
- **system-manager for the non-NixOS Linux hosts** (hoenn,
  `numtide/system-manager`) — `systemConfigs.<host>` manages `/etc` and
  systemd units on a stock distro without converting it. Two lines carry it:
  `system-manager.allowAnyDistro = true`, and an `mkForce` of
  `environment.etc."environment.d/10-system-manager.conf"` putting
  `/run/system-manager/sw/bin` ahead of `/usr/bin` on PATH. Notable detail:
  the same host (`sootopolis`) exists twice in that flake, once as a full
  NixOS config and once as a system-manager config, sharing feature modules
  and the auto-upgrade module. Directly relevant to the Debian boxes here,
  which today get nothing from the fleet config.
- **Auto-upgrade that cannot hurt you** (hoenn
  `nix/modules/auto-upgrade/default.nix`) — one shared attrset applied to
  NixOS, nix-darwin and system-manager: `operation = "boot"` with
  `allowReboot = false` and `upgrade = false`, so the timer builds and stages
  the generation but never reboots a laptop out from under its user;
  `persistent = true` + `randomizedDelaySec = "45min"`; and the unit gains
  `Restart = "on-failure"`, `RestartSec = "15min"`, `StartLimitBurst = 2`,
  `StartLimitIntervalSec = "1h"`, so a broken flake retries twice and then
  stops instead of hammering all night. nix-darwin has no `autoUpgrade`, so
  the darwin side is a hand-rolled `launchd.daemons` script; its one clever
  bit is a deterministic per-host stagger — `cksum` the hostname, modulo 45
  minutes, sleep that long — which spreads a fleet across a window with no
  coordination and no fresh randomness on every activation.
- **OpenTofu state in B2 over the S3 backend** (sinnoh/johto
  `terraform/providers.tf`) — Backblaze speaks enough S3 to be a tfstate
  backend once you turn off the AWS-only handshakes:
  `skip_credentials_validation`, `skip_metadata_api_check`,
  `skip_region_validation`, `skip_requesting_account_id`, `skip_s3_checksum`
  and `use_path_style`. Cheap state hosting where the backups already live.
  The caveat is real and their AGENTS.md states it plainly: "The B2 state
  backend does not lock OpenTofu state. Review the plan before you apply, and
  never run concurrent applies." Adopt the flag set and the warning together,
  or use a locking backend.

## Caching and builders

- **OrbStack's NixOS machine as flake-managed host and builder**
  (josephst `hosts/nixos/orbstack/` +
  `hosts/darwin/Josephs-MacBook-Air/orbstack.nix`) — the OrbStack
  guest is a real nixosConfiguration (lxc-container profile +
  OrbStack's generated module, bootloaders forced off), and the Mac
  wires `nix.buildMachines` at OrbStack's local listener
  (`127.0.0.1:32222`, `~/.orbstack/ssh/id_ed25519`; the GUI ssh
  helper fails when the daemon invokes it as root). Alternative to
  the qemu linux-builder: instant boot, dynamic memory; cost is a
  dependency on the OrbStack app running.
- **niks3 with GitHub-OIDC push auth** (CnTeng
  `nixos/modules/services/niks3.nix`) — Mic92's S3-backed cache
  server (theirs on Cloudflare R2) with `oidc.providers.github`
  scoped to the repo, so CI pushes authenticate with short-lived
  OIDC tokens instead of a stored signing secret. Relevant to the
  cachix signing key in CI secrets; `NIX_CACHE_PRIORITY=50` ranks it
  below cache.nixos.org.
- **EC2 instances as remote builders — a dedicated profile**
  (lovesegfault `modules/nixos/profiles/ec2-builder.nix`) — documents
  the EC2 eval caveats up front (hostname set dynamically, so no
  hostname guard; EBS-image hosts import amazon-image.nix themselves),
  mounts `/nix/var/nix/builds` as tmpfs (`size=33%`,
  `huge=within_size`) so builds never touch EBS, enables nix-ld. The
  same profile shape ports to GCE; pairs with the aws-image item in
  GCE projects below.
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
- **Lock the builder account down in `authorized_keys`** (johto
  `nix/hosts/nixos/goldenrod/remote-builder.nix`) — the builder user's key
  line is `from="10.254.2.2",restrict,command="${pkgs.nix}/bin/nix-store
  --serve --write" ssh-ed25519 ...`: source-IP pinned, every forwarding and
  PTY feature off, and the only reachable command is the store-serve
  protocol. The client half is `nix.buildMachines` with the private key from
  sops and `builders-use-substitutes = true`. The existing remote-builder
  items here all stop at "dedicated user + trusted-users"; this is the line
  that makes that user harmless if the key leaks.

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
- **Service catalog fan-out** (jdheyburn `catalog.nix`, 301 lines) —
  one `services.<name>` entry (host, port, module list, dashboard
  metadata) drives five consumers: Caddy vhost, AdGuard DNS rewrites,
  blackbox-exporter probe targets, per-node Prometheus scrapes, and
  Dashy dashboard tiles. Mechanism is plain attrsets — build it on
  typed options (the GaetanLepage host-registry item) if adopted; the
  *scope* of declare-once/everything-follows is the idea.
- **OCI container privilege hardening** (clo4
  `hosts/homeserver1/minecraft/servers/family.nix`) — pinned uid/gid
  system user + group, `systemd.tmpfiles` for the data dir (0770), and
  `virtualisation.oci-containers.containers.<n>.user = "uid:gid"` so
  root is dropped at launch and the uid holds inside the container.
  Directly applicable to helium's openhab container, which runs with
  defaults. Side nugget: serve on a non-default port + SRV record so
  scanners miss it and clients need no port.
- **Pin the openhab container by digest** (LongerHV
  `modules/nixos/otbr.nix` shows the shape: `nix-prefetch-docker` with
  `imageDigest` + `hash`, regen command committed as a comment) —
  helium's oci-container runs a mutable `:latest` tag today, so the
  deployed service isn't reproducible and upgrades happen whenever
  podman pulls. Closer to a bug than an idea; a version tag is the
  minimum fix, a digest pin the full one.
- **Ephemeral file-sharing jail** (chvp
  `modules/services/data-access/default.nix`) — a NixOS container
  with `ephemeral = true`, read-write and read-only bind mounts of
  the same data directory, sftp on a non-standard port, and
  basic-auth nginx autoindex in front: a sacrificial box for handing
  files to third parties, reset on restart.
- **Tailnet-only ingress through one Tailscale operator ProxyGroup** (johto
  `k8s/tailscale-private-ingress/proxy-group.yaml`, `k8s/private-ingress/*.yaml`)
  — a `ProxyClass` pins the proxy to one node with a nodePort range for static
  endpoints, a `ProxyGroup` of `type: ingress` runs it, and then every private
  app is a five-line Ingress with `ingressClassName: tailscale` and a
  `tailscale.com/proxy-group` annotation. Each one becomes
  `<name>.<tailnet>.ts.net` with a real certificate, no per-app sidecar and no
  public DNS. The alternative shape to per-service `tailscale serve`, and the
  reason their public ingress stays a separate, much smaller surface.
- **A runbook written for someone half-awake** (johto `docs/tailscale-services.md`)
  — add-a-service template, the reconcile commands with an explicit
  `--context`, how to tell the route came up, and a fenced "if a name is
  genuinely blocked" section whose rules are refusals: do not delete a service
  just because the name exists; check for a `tailscale.com/owner-references`
  annotation first; and re-derive the OAuth token in its own shell so the
  DELETE cannot run against a stale one. That last one is the interesting
  move — the danger is designed out of the copy-pasteable block rather than
  warned about. Better model for per-host runbooks than srid's `mod.just`
  where the procedure has judgement in it.
- **One local chart, N values blocks** (johto `k8s/charts/servarr/`) — seven
  near-identical *arr apps share a single in-repo Helm chart whose values
  carry name, port, image, database secret, legacy-config path and optional
  exporter; each app is a ~15-line HelmRelease. `check-k8s` renders local
  charts, so the abstraction is still schema-validated. The answer to seven
  copies of the same Deployment.
- **Minimal fleet log aggregation** (sinnoh
  `nix/hosts/nixos/canalave/grafana/loki.nix` + `nix/nixos/services/alloy.nix`)
  — single-binary Loki with the filesystem store, `replication_factor = 1`,
  in-memory ring, compactor retention at 30d, analytics off; every host runs
  Alloy with a ~25-line config that ships only the journal, relabelling
  `__journal__systemd_unit` to `unit` and stamping the hostname. About 40
  lines each and no object storage. The cheap version of the fleet
  observability idea noted from shikanime and barrucadu.
- **Flux ordering as an explicit dependency graph** (sinnoh/johto
  `k8s/flux-system/*.yaml`) — one Kustomization per component, each with
  `dependsOn` and `wait: true`, so secrets reconcile before postgres, which
  reconciles before the apps that hold its roles. Worth copying if any
  GitOps-shaped deploy lands here: the ordering lives in data, not in a
  README telling you what to apply first.

## Sandboxing and agents

- **Per-app bubblewrap wrappers** (kurnevsky `modules/sandbox.nix` +
  `modules/sandbox/bwrap.nix`) — `wrap drv bins` symlinkJoins
  sandboxed launchers over the original package, preserving
  override/overrideAttrs, with runtime escape hatches (`WHITELIST`,
  `WITH_NETWORK`, `UNSANDBOXED`) and a fake `flatpak` shim answering
  the xdg document portal so file-access prompts still work. The
  per-app mechanism this section lacks: agentspace is VMs, nono is
  Landlock, firejail is profiles.
- **torjail** (kurnevsky `modules/torjail.nix`) — a network namespace
  whose traffic is forced through tor's `TransPort`/`DNSPort` via
  nftables NAT: any program runs over Tor without app-level SOCKS
  config. Extends the installed tor/torsocks pair.
- **firejail-wrapped GUI apps** (mrcjkb
  `desktop-programs/firejail.nix`) — NixOS's typed
  `programs.firejail.wrappedBinaries` ships sandboxed browser
  wrappers; the lightweight GUI-app sandbox layer for the Fusion/UTM
  VMs' chromium/firefox, a niche nothing else in this section covers.
- **nono — Landlock sandbox for agent processes** (marcusramberg
  `home/packages.nix`; in nixpkgs) — kernel-enforced filesystem
  sandboxing aimed at AI agents/MCP workloads. First
  kernel-enforcement candidate in this section; Linux-only (Landlock),
  so fleet hosts and VMs, not neon.
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
- **Skill evals checked in beside the skill** (hoenn
  `nix/modules/aly/skills/nix/evals/*.json`) — one JSON file per scenario
  with `skills`, `query`, `expected_behavior`, and the field that earns its
  keep, `baseline_without_skill`: what the agent does with the skill absent.
  There is no runner — you score by watching an agent — but writing the
  baseline forces the skill to justify its own existence, which is the
  empirical counterpart to the weakness razor in the rule-authoring skill.
  Their own README admits the gap: deterministic unit tests for the skill's
  helper scripts are still missing. Four scenarios for a ~120-line skill is
  the right ratio to copy.
- **Null results are evidence** (hoenn `nix/modules/aly/skills/why/SKILL.md`)
  — the skill enumerates seven evidence categories, queries all of them, and
  requires reporting the categories that came back empty alongside the ones
  that hit, on the grounds that how a decision was recorded is itself a
  finding. Same instinct as the prefer-weak-conclusions rule in CLAUDE.md;
  worth a line wherever an agent here summarises a search.
- **AGENTS.md as four operational sections** (hoenn `AGENTS.md`, ~30 lines) —
  where files live, how to check a change, how to deploy, how to handle
  secrets. No philosophy. The two lines that earn their place are the deploy
  guards: "Never deploy only to test a configuration" and "Do not use a bare
  `blzrd switch` unless you mean to target every registered node." Equivalent
  guards for the remote `make` targets here would be cheap.
- **Secrets into a microVM without giving the guest an identity** (johto
  `nix/hosts/nixos/goldenrod/vms.nix` + `cherrygrove/microvm.nix`) — a oneshot
  unit ordered `before` and `requiredBy` the `microvm@<name>.service` installs
  the sops-decrypted files into its own `RuntimeDirectory` (mode 0750), and
  the guest declares a read-only virtiofs share mapping `/run/<name>-secrets`
  to `/run/host-secrets`. The guest needs no age key and no sops, the material
  never reaches the store or a disk, and it disappears with the runtime
  directory. Directly applicable to the sandboxed-agent microVM item above,
  which otherwise has no answer for credentials.

## GCE projects (self-originated)

- **AWS image target beside the GCE one** (research pass 2026-09-03;
  references: NixOS/amis, the AWS NitroTPM/Secure Boot deep-dive, the
  AL2023 uefivars worked example) — the repart+UKI pipeline ports to
  EC2 nearly 1:1: build a UEFI variable store carrying the ephemeral
  cert as PK/KEK/db with awslabs `python-uefivars`, upload the raw
  image as an EBS snapshot with awslabs `coldsnap` (no S3/vmimport),
  then `aws ec2 register-image --boot-mode uefi --uefi-data ...
  --tpm-support v2.0 --imds-support v2.0 --ena-support`
  (`--architecture arm64` for Graviton; registration must be CLI).
  Reuse nixpkgs `amazon-image.nix` only as the profile layer (ena
  module, NVMe io_timeout, ec2-data/amazon-init — likely disabling
  amazon-init the way the GCE image avoids on-instance rebuilds), the
  role google-compute-config plays today; srvos `hardware-amazon` is
  the curated baseline to skim first. NitroTPM means the TPM-sealed
  keys idea (§3) works on EC2 too. Nice-to-haves: account-level
  serial-console enable; an IMDS `spot/instance-action` poller if spot
  ever matters.
- **GCE pipeline refinements** (same research pass) — register the
  `IDPF` guest-OS feature + `idpf` kernel module beside the existing
  gve pattern (C4/C4A present IDPF NICs, not gVNIC — same story, one
  generation later); Confidential VM is one image variant away
  (`SEV_SNP_CAPABLE`/`TDX_CAPABLE` guest features; UEFI+vTPM already
  in place; launch with `--confidential-compute-type=SEV_SNP`);
  `--architecture=ARM64` is required on an aarch64 `images create`
  and easy to miss; use an image `--family` + `gcloud compute images
  deprecate` for lifecycle instead of tracking image names in the
  Makefile; `eth0.useDHCP` covers v4 only — dual-stack subnets need
  the v6 enable; watch the google-guest-agent v2 ("core plugin")
  rewrite land in a lock bump via the closure diff.
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

- **apple/container — in use, not yet declarative** (verified on neon
  2026-09-23, apple/container 1.4.1 on macOS 27.0) — Apple's native
  container CLI runs one lightweight VM per container
  (Containerization.framework), OCI only, Apple silicon only, macOS 26
  the effective floor. It is installed from Apple's signed pkg (see
  workarounds.nix for why not from nixpkgs) and works: egress, DNS,
  published ports, host-to-container and container-to-container traffic
  all pass with tailscale running, so the "VPN/tunnel interfaces break
  vmnet port forwarding" warning does not reproduce here. Images built
  by nix need one conversion step: dockerTools emits a Docker archive
  and `container image load` wants an OCI layout, so the
  `container-server-oci` package pipes it through skopeo. Two upstream
  bugs to watch rather than fix: #1881/#1882 (container subnet routing
  breaks when a competing default route appears and does not self-heal
  — neon already carries en0 + utun4) and #2275 (on macOS 27.0 the
  apiserver never finishes startup if `com.apple.pfd` is unresponsive,
  hanging every command). The open decision is declarative management.
  halfwhey/nix-apple-container is still the integration to copy
  (containers as launchd agents, nix2container layers streamed from
  store paths, optional Linux builder containers as a linux-builder-VM
  alternative), but it is tagged v0.0.6 from April with main tracking
  1.4.1, its launchd bootstrap bug (#8) and the fix for it (#9) both
  open, and the module deletes containers it does not declare — which
  fights the ad-hoc images on neon. Nothing else there is at stake:
  `container system property ls` on neon returns pure defaults, and
  neither `~/.config/container/config.toml` nor
  `/usr/local/etc/container/config.toml` exists, so the runtime's whole
  config surface is unclaimed and a nix-written TOML file could take it
  without displacing anything.
  For docker-CLI compatibility the reference remains BrianHicks
  `dotfiles/container/default.nix`: `socktainer` as a Docker-socket API
  shim plus a committed preset script (`container system property set
  build.rosetta true`, cpu/memory budgets) as the config surface the
  CLI lacks.
- **containers and container machines need different permissions**
  (measured on neon 2026-09-23 with the `container-server-oci` image) — a
  container is a container; a container machine is a VM with a persistent
  disk (2.4G for this image), and the two have separate permission
  surfaces. For containers the question is which of the default set to
  drop, not what to add: `container run` already grants fourteen
  capabilities (AUDIT_WRITE, CHOWN, DAC_OVERRIDE, FOWNER, FSETID, KILL,
  MKNOD, NET_BIND_SERVICE, NET_RAW, SETFCAP, SETGID, SETPCAP, SETUID,
  SYS_CHROOT) and `--cap-drop ALL` removes them. The runtime also mounts
  /proc, /sys, /dev, /dev/pts, /dev/shm and cgroup2 already, so the only
  thing NixOS's `specialfs` activation snippet still wants is /run.
  Measured against this image: `--cap-add SYS_ADMIN` reaches `running`
  with nothing failed, SYS_ADMIN being what lets activation mount /run;
  the default set plus `--tmpfs /run --tmpfs /run/wrappers` also boots,
  but nscd fails because its unit asks to keep SYS_ADMIN; `--cap-drop ALL`
  with those same tmpfs mounts still gets systemd to PID 1 and loses
  systemd-journalctl.socket as well, which is what makes `systemctl`
  queries answer "Transport endpoint is not connected". So the floor is
  zero capabilities, paid for with nscd and journal access. Machines take
  no `--cap-add` at
  all — the knobs are cpus, memory, kernel, home-mount and virtualization —
  and they do not boot this image. Apple injects `/sbin.machine/init` at
  creation: a /bin/sh script that sources /etc/os-release under `set -e`
  and ends in `exec /sbin/init`, none of which NixOS creates before its
  activation script, which that boot never reaches. Linking /bin/sh,
  /sbin/init and /etc/os-release into the image walks the failure from
  exec-ENOENT to exit 1 to exit 127; the next blocker is `chown`, which the
  script runs unconditionally because `[ -S ${SSH_AUTH_SOCK} ]` is true
  when the variable is unset. Machine support therefore means putting
  coreutils on the image's PATH — an FHS layer the container target does
  not need, and worth doing only if a NixOS container machine is wanted
  alongside the NixOS VMs we already build.
- **a container is not on the tailnet, but it reaches the whole tailnet**
  (measured on neon 2026-09-23) — a container gets its own address on a
  NAT'd vmnet segment (192.168.64.0/24, gateway .1 on the host) and is not
  a tailscale node: it has no tailnet identity and peers cannot address it.
  Egress, though, transits the host's routing table, so from a plain
  `alpine` container both tailnet peers answered ICMP — helium at 5ms, the
  remote `go` node at 175ms. Anything running in any container therefore
  reaches every tailnet peer with neon's routes, and inbound a published
  port binds every interface including utun4 unless the publish spec names
  `127.0.0.1`. `container network create --internal` does isolate: on 1.4.1
  ICMP and TCP to both a tailnet peer and a public address were all
  blocked, which contradicts upstream #2062 (arbitrary outbound TCP leaks
  from hostOnly networks) — that issue blames a test that only passed
  because DNS failed, and this check used raw addresses. The catch is that
  an internal network has no egress at all, so an isolated builder cannot
  reach substituters and every input has to be pushed from the host, which
  is what `builders-use-substitutes = false` already does.
- **`container system kernel` is not updated by a runtime upgrade** (hit
  on neon 2026-09-23) — installing apple/container 1.4.1 over 1.0.0 left
  `default.kernel-arm64` pointing at `vmlinux-6.12.28-153`, downloaded in
  August 2025, even though `system property ls` advertised the kata 3.32.0
  kernel. That old kernel is built with `CONFIG_TMPFS_XATTR` and
  `CONFIG_TMPFS_POSIX_ACL` unset, so tmpfs holds neither file capabilities
  nor ACLs. NixOS keeps its setuid wrappers on a tmpfs at /run/wrappers and
  each one reads its own capabilities through /proc/self/exe at startup, so
  every wrapper aborted -- `sudo`, `su`, `mount`, `passwd`, `chsh`,
  `newgidmap`, `newuidmap`, `fusermount`, `sg`, `sudoedit` -- with "cannot
  get capabilities for /proc/self/exe: Not supported", and resolvconf's
  setfacl on /run/resolvconf failed the same way. `container system kernel
  set --recommended` installs 6.18.35, which has both options set: `setcap`
  on /run/wrappers then succeeds and `sudo` works. The old kernel stays on
  disk, so the change reverts with `--binary`. Same shape as the stale
  helper processes after an upgrade: the installer replaces binaries and
  leaves downloaded state alone, so check both after every update.
- **halfwhey nix-builder as a build venue** (`ghcr.io/halfwhey/nix-builder`,
  tags `<builder-version>-nix<nix-version>`, currently `v2-nix2.35.2`,
  multi-arch amd64/arm64, MIT) — the `linux-builder` half of
  nix-apple-container runs that image as a container to build
  `aarch64-linux` and `x86_64-linux` derivations on macOS. That is an
  alternative to both halves of our current arrangement: neon's qemu
  linux-builder VM for aarch64 and shipping x86_64 work to helium. Its
  x86_64 builder pins the Kata `3.24.0` kernel through `container run
  --kernel` to dodge Rosetta regressions with newer kernels, which is the
  kind of detail that argues for copying their pinning rather than
  re-deriving it. Adoptable on its own, without the container-reconciling
  half of the module that we do not want.

  Tried on neon 2026-09-23: the image builds an `aarch64-linux`
  derivation over nix's remote-store protocol, so the mechanism works.
  Three things stand in the way of using it as-is. Its SSH private key is
  committed to the public repo, and `--publish 31022:22` binds every
  interface, not localhost as the README claims -- root on the builder was
  reachable from both the LAN address and the tailnet address in the test.
  `--publish 127.0.0.1:31022:22` fixes that (verified: connections from
  the LAN address are then refused), and a locally generated key would fix
  the rest. Their default port 31022 is already taken on neon by something
  bound to `*` that lsof will not name without sudo. And `/nix/store` in
  the container is not a volume, so the builder re-fetches its 1.3GB of
  store on every start. Note also that their `buildMachines` entry
  advertises only `big-parallel`, where neon's linux-builder advertises
  `nixos-test` as well so NixOS VM tests are accepted; the image carries no
  qemu. So this is an addition for `x86_64-linux`, which we cannot build
  locally at all today, rather than a replacement for the aarch64 VM.
- **nix2container instead of a tarball in the store** — the same module
  loads nix-built images with nix2container: only a small JSON manifest
  lands in the Nix store and the layers stream from existing store paths at
  activation. Our `container-server-oci` is built by dockerTools and
  converted with skopeo, which streams the Docker archive so only the OCI
  archive reaches the store -- still a ~310MB path per rebuild, where
  nix2container would write a manifest. Worth switching if the image starts
  being rebuilt often; the cost is one more flake input.
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
- **Egress policy for a pod that must fetch arbitrary URLs** (sinnoh
  `k8s/vaultwarden/network-policy.yaml`) — a `default-deny` NetworkPolicy for
  the namespace, then an explicit allow: DNS to kube-dns, 5432 to the database
  pod, and 80/443/587 to `0.0.0.0/0` minus every RFC1918/CGNAT/link-local/
  documentation/multicast block — *and* minus the operator's own three public
  ingress IPs, with the comment "Public ingress addresses must not bypass
  internal isolation". That last exclusion is the part worth stealing: without
  it, a pod allowed to reach the internet can loop back in through the public
  edge and reach services the policy just denied it. The bogon list is
  copy-pasteable as-is for any SSRF-prone workload (icon fetchers, webhook
  senders, feed readers).
- **Stub-zone DNS for overlay names** (sinnoh `k8s/tailscale-dns/coredns.yaml`
  and johto `nix/hosts/nixos/olivine/private-dns.nix`) — in-cluster, a
  `coredns-custom` ConfigMap forwards `<tailnet>.ts.net:53` to
  `100.100.100.100` with a 30s cache, so pods resolve MagicDNS names; on the
  hosts, a ~10-line CoreDNS `hosts` block serves a `johto:53` zone bound to
  the WireGuard address, ordered `after`/`requires` the wireguard unit. Two
  small pieces that stop overlay hostnames from being a hosts-file problem.
- **Drop query parameters from the reverse proxy access log** (johto
  `k8s/traefik/config.yaml`) — `--accesslog.fields.queryparameters.defaultmode=drop`
  with JSON access logs. Tokens and reset links travel in query strings;
  logging them turns the log store into a credential store.

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
- **An object-storage bucket as a lazily-mounted filesystem** (johto
  `nix/modules/b2media/default.nix`) — B2 buckets declared as `fileSystems`
  entries with `fsType = "rclone"` and options carrying the sops-provided
  rclone config, `x-systemd.automount` + `nofail` +
  `x-systemd.after=network-online.target` so a bucket mounts on first access
  and a dead network never blocks boot, and `vfs-cache-mode=full` with
  read-ahead, buffer and cache-age tuned per media profile (audio vs video) by
  a typed option. The rclone counterpart to the lazy NAS-mount item above; the
  per-profile tuning is the transferable part.

## lib and module mechanics

- **Standalone evalModules data layer** (zentralwerk/network
  `nix/lib/config/`): the whole site — nets, hosts, VLANs, cabling — is
  one typed option tree evaluated with `lib.evalModules` *outside* NixOS,
  exported as `self.lib.config`, consumed by hosts and plain packages
  (device scripts, reports) alike, with a large eval-time assertion suite
  over the dataset (duplicate IPs/VLANs/ports, cross-references). The
  grown-up version of the fleet-axes idea if the fleet ever gets big
  enough to want hosts-as-data; their wart to avoid: options.nix is
  imported twice (standalone + NixOS), blocking readOnly on derived
  options.
- **Validate rendered configs with their real parser at build time**
  (zentralwerk/network `container/lxc-config.nix`): the generated lxc
  config is checked in the sandbox by compiling a tiny C program against
  liblxc and calling load_config — because liblxc silently ignores
  everything after a bad line. Generalizes to `nginx -t`, `sshd -t`,
  `nft -c` as derivation checks on any config our modules render.

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
- **A mesh service as a typed module plus a peer registry** (hoenn
  `nix/modules/syncthing/{options.nix,_devices.nix,service.nix}`) — device
  IDs live in one `_devices.nix` attrset; each shared folder is an option
  whose submodule *defaults* carry the path, the stable folder id, the peer
  list and the versioning policy; a host then writes only
  `hoenn.syncthing.folders.sync.enable = true`. The shape generalises to any
  service whose config must be identical on every peer and silently rots when
  it is not.

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
- **llama-swap on macOS with models as fixed-output derivations**
  (mitchty `nix/darwinModules/llama-swap.nix` + `fetchhf` in
  `nix/lib.nix`) — HuggingFace GGUFs become hash-pinned `fetchurl`
  derivations (cacheable, GC-able store paths instead of `~/.ollama`
  state); a launchd daemon runs llama-swap, lazy-loading/swapping
  models with per-model TTLs and exclusive groups within a RAM budget,
  YAML generated from nix. The declarative story for neon's currently
  unmanaged ollama; a lighter `ollama.nix` launchd module sits beside
  it if TTL-swapping is overkill.

---

# 6. Package and app candidates

- **hyperfine** for benchmarks
- **fq** (https://terminaltrove.com/fq/) — jq for binary formats

## CLI shortlist (September 2026 sweeps — 18-repo rounds)

The picks from ~90 new packages across the two September rounds; the
full lists live in the per-repo review record.

- **rbw** — Bitwarden CLI with a background agent (no re-login per
  call); candidate replacement for bitwarden-cli
- **gron** / **jless** / **dasel** — JSON to greppable lines; JSON/YAML
  TUI pager; jq-style queries over JSON/YAML/TOML/CSV in one tool
- **moreutils** — sponge/vipe/ts/chronic classics
- **pv** — pipe progress meter
- **ipcalc** / **dateutils** — subnet math; date arithmetic CLIs
- **xh** — fast httpie-style HTTP client
- **ov** — feature-rich pager; **gitu** — magit-style git TUI
- **termshark** — wireshark TUI (pairs with the wireshark cask)
- **grc** — generic colouriser for ping/dig/mount output
- **caligula** — TUI disk imaging (pairs with the installer ISO)
- **taplo** — TOML formatter/linter (nothing formats TOML here)
- **vhs** — scripted terminal recording → GIF (beside asciinema)
- **pet** / **ghq** — snippet manager; repo organizer under one root
- **rage** — Rust age implementation (faster than age)
- **git-sizer** — repo-size analysis; **stress-ng**/**fio** — CPU and
  disk load tools for server validation
- **navi** — fzf cheatsheet TUI (see the versioned-cheatsheets idea)
- CTF kit for the external security flake, not home.packages:
  gobuster, rustscan, sqlmap, stegseek, binwalk, pwndbg, ghidra-bin,
  john, hexedit, patchelf (berbiche `profiles/ctf/`)
- From the 2026-09-03 eight-repo round: **rustic** (Rust
  restic-compatible backup engine, config-file driven),
  **fast-nix-gc** (much faster store GC, Mic92), **zsh-histdb** +
  oddlama's skim picker (sqlite zsh history, the daemon-less atuin
  alternative), **lnav** (log navigator TUI with SQL over log lines),
  **doggo** (DNS client with DoH/DoT/DoQ + JSON), **mdq** (jq for
  markdown), **ccusage** (Claude Code token/cost reports),
  **nix-your-shell** (`nix develop` lands in zsh not bash), **page**
  (neovim as $PAGER), **realise-symlink** (store symlink → writable
  copy in place), **git-fuzzy**, **gallery-dl** (yt-dlp's
  image-gallery sibling), **uxplay** (AirPlay receiver on Linux —
  audit-relevant twist on the AirPlay TODO), classics **expect** /
  **dos2unix** / **mediainfo**
- From the 2026-09-03 Tier-2 round (two independent sightings marked
  ×2): **tcpdump** (a real gap — never declared despite the
  network-debugging habit), **hydra-check** ×2 (has Hydra built X on
  channel Y? — pairs with the stable-base policy), **difftastic** ×2
  (structural syntax-aware diff; `diff.external` candidate),
  **git-lfs** ×2 (absent from the git setup), **blocky** ×2
  (single-binary filtering DNS, helium LAN candidate), **searxng** ×2
  (self-hosted metasearch, helium service candidate), **resholve**
  (resolve every command in a shell script to a store path — the
  proper packaging for `~/.bin`), **manix** (CLI search over
  nix/NixOS/HM docs and options), **nix-search** (fast indexed
  nixpkgs search), **systemctl-tui** (units + logs in one TUI),
  **eternal-terminal** (roaming-surviving remote terminal with
  scrollback), **tmate**/**upterm** (instant terminal sharing),
  **dumbpipe** (iroh p2p pipe), **broot** (tree navigator with staged
  ops), **yj** (YAML↔TOML↔JSON↔HCL), **minio-client** (S3 CLI for
  the offsite thread), **proxychains-ng** (broader torsocks),
  **prettyping**, **signal-cli**, **scrcpy** (Android mirroring),
  **cargo-sweep**, **git-part-pick** / **git-auto-fixup** (partial
  cherry-pick; blame-driven fixups), **advcp** (cp/mv with progress),
  **nix-monitored** (transparent nom wrapping), **feedback**
  (declarative watch-loops), **scrutiny** (SMART dashboard),
  **rayhunter** (EFF stingray detector — security-research lane),
  **fleetctl** (osquery fleet CLI), **tpm2-tools** (companions to the
  TPM2 unlock item), **odt2txt**, **w3m**, **carbonyl** (Chromium in
  the terminal), **aerc**, **newsboat**, **marp-cli**/**mdp**
  (markdown slides), **playerctl** (VM media control), **msedit**;
  casks **aldente** (battery charge limit), **launchcontrol** (GUI
  launchd manager), **topnotch**, **macs-fan-control**,
  **languagetool-desktop**, **element**, **balenaetcher**, brew
  **sleepwatcher** (scripts on sleep/wake); paid, noted only:
  daisydisk, macupdater
- From the 2026-09-03 final round (×2 = two sightings): **sshfs** (a
  real gap given the fleet-over-ssh workflow), **zbar** (decode QR
  codes — the pair to qrencode), **backrest** ×2 (restic web
  UI/scheduler), **bat-extras** ×2, **diffoscope** (deep recursive
  archive/binary diff), **rr** (record/replay debugger), **nix-diff**
  (why two derivations differ), **fclones** (duplicate finder),
  **par2cmdline-turbo** (bit-rot parity for the backup thread),
  **reptyr** (reattach a process to tmux), **podman-tui**,
  **openconnect** (AnyConnect-compatible VPN client), **scc**,
  **perf**, **websocat**, **pizauth** (OAuth2 agent for CLI tools),
  **sherlock** (OSINT username search), **translate-shell**,
  **copyparty** (single-binary file server; helium candidate),
  **audiobookshelf** (helium media candidate), **lrzsz**,
  **mktorrent**, **isd**, **hydra-check** and **difftastic** (both
  re-confirmed ×2 across rounds); agent lane: **rtk** (token-cheap
  bash rewriting hooks), **agent-browser**, **openspec**, **handy**
  (local push-to-talk); cask **disk-inventory-x** (free daisydisk);
  security flake: metasploit, radare2, aircrack-ng, dsniff,
  arp-scan, exploitdb

## CLI, cross-platform (traxys survey)

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
- **sshd-or-reboot watchdog** (`FailureAction = "reboot"` on sshd, was
  batch B10) — decided 2026-09-05: a persistent sshd failure reboot-loops
  with no exit. The upstream pattern pairs it with systemd-boot boot
  counting (Nth failed boot falls back to the previous generation);
  nitrogen boots GRUB/BIOS, so only the loop half would land. The loop
  also fires on a bad `switch` (into the now-default bad generation) and
  shrinks the provider-console rescue window to seconds. The failure it
  insures against is rare anyway: NixOS validates sshd_config at build
  and regenerates missing host keys in preStart. Side note: the surveyed
  snippet targets `systemd.services.openssh`, but the unit is `sshd` — as
  written it is a no-op. If reachability insurance is ever wanted,
  Tailscale SSH as an independent second door is the better direction
  (its own security discussion).
- **GC timer jitter** (`nix.gc.randomizedDelaySec`/`persistent`) —
  skipped 2026-09-05: Persistent=true is already the NixOS default
  (verified on the generated timer); jitter addresses contention that
  independent machines don't have.
- **sudo-rs** — skipped 2026-09-05: not needed, and not a drop-in here —
  the fleet's sudo carries execWheelOnly (hardening.nix, relaxed on the
  GCE image) and pam_rssh wiring that would need re-verifying.
- **ssh client hardening baseline** (HashKnownHosts / VerifyHostKeyDNS /
  StrictHostKeyChecking / ForwardAgent-no in `Host *`) — skipped
  2026-09-05: ForwardAgent scoping already exists via the fleet match
  block (and a `ForwardAgent no` in `"*"` would first-match-win over it,
  breaking pam_rssh sudo); strict checking is covered by the filed
  accept-new/knownHosts/forge-pinning items; HashKnownHosts hides names
  this public repo already lists; VerifyHostKeyDNS is a no-op with no
  SSHFP records published and no DNSSEC-validated resolution.
- **Tailnet-scoped ssh canonicalization + XDG ControlPath** — skipped
  2026-09-05: the explicit fleet match block already scopes agent
  forwarding (and covers `dev`, which is off-tailnet on a plain IP);
  XDG_RUNTIME_DIR ControlPath is Linux-only and the primary ssh client
  is the Mac.
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
- **Homebrew on NixOS** (hoenn `nix/modules/homebrew/default.nix`) —
  linuxbrew plus a `system.activationScripts` step that symlinks a `buildEnv`
  of coreutils, gcc, glibc.bin and friends into both `/bin` and `/usr/bin`,
  plus a ~50-entry `programs.nix-ld.libraries` list. That is fighting the
  platform to run binaries nixpkgs already has. Only defensible for a
  specific formula that exists nowhere else, and then in a container, not as
  writes to `/bin`.
- **`homebrew.greedyCasks = true`** (hoenn
  `nix/modules/darwin/homebrew/casks.nix`) — auto-updates every cask on each
  `darwin-rebuild`, making a rebuild nondeterministic by design. Against the
  same reasoning that settled `cleanup = "none"` here.
- **hermes-agent** (hoenn `nix/modules/hermes/hermes.nix`) — a self-hosted
  agent stack wired to ElevenLabs TTS, Browserbase and Firecrawl. Three cloud
  dependencies and a sops-held key bundle for something whose appeal would be
  running locally.
- **`LaunchServices.LSQuarantine = false`** (hoenn
  `nix/modules/darwin/defaults.nix`) — third sighting, declined again;
  Gatekeeper's first-run prompt is worth the two seconds.

---

# 8. Survey log

What was surveyed when; sections above carry per-item attribution.

- 2026-08-31 — `zentralwerk/network` (C3D2 Dresden building network:
  2 NixOS servers, 82 LXC router containers, 20 switches, 77 OpenWrt
  APs, all generated from one data model). Harvested: namaka snapshots,
  cold-standby flag file, self-fencing deploys, standalone evalModules
  data layer, parser-validated rendered configs. Noted but not taken:
  per-AP OpenWrt image building (no APs here), GPG dummy-secrets swap
  (inferior to our sops setup — their secrets land in the world-readable
  store), hostname-regex module selection and an nmap IFD as warts.

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
- 2026-09-01/02 — `madmaxieee/nix-config` and `malob/nix-config`.
  Adopted immediately: dock mru-spaces/show-recents,
  `init.defaultRefFormat = "files"` (jj/reftable), captive-browser (own
  survey). Standouts (filed 2026-09-02): malob's `users.primaryUser` typed
  identity + `makeOverridable` host template (fixes the hardcoded-user
  follow-up), Claude Code managed-settings.json layer, stealth
  mode/loginwindow hardening, `prefmanager`; madmaxieee's
  skills-as-flake-inputs. Skipped: nix-homebrew vs. the cleanup="none"
  policy, Determinate Nix (breaks linux-builder — malob's own TODO).
- 2026-09-02 — six-repo parallel survey: `totoroot/dotfiles`,
  `enocla/nix-config`, `mrkuz/macos-config`, `tjmaynes/config`,
  `shikanime-labs/machines`, `eh8/chenglab`. Shortlist filed above
  (Time Machine target + kopia-shape backup, GitHub App token for
  update-lock, jj guards/revsets, colorMoved). The `nix.gc.automatic`
  "gap" two reviewers reported was false — nix-settings.nix sets it.
  Not yet filed, in the conversation record: mrkuz's ephemeral
  `nix run .#*-vm` NixOS VMs on macOS + minimize.nix, tjmaynes's
  refusing Makefile targets and docs-drift/hygiene tests, eh8's
  remote initrd unlock and `sops.templates`, shikanime's comin GitOps
  and VictoriaMetrics fleet observability, enocla's sops-encrypted
  private ssh inventory, assorted macOS defaults and packages.
  Unanimous skips: Determinate Nix/Lix (third sighting), unstable-only
  nixpkgs, stringly identity blobs.
- 2026-09-02 — ten-repo parallel survey, deduped against this file at
  source: `franckrasolo/dotfiles.nix`, `dustinlyons/nixos-config`
  (delta since the 2026-07-07 survey — thin, as expected),
  `mitchty/nix`, `jdheyburn/nixos-configs`, `clo4/nix-dotfiles`,
  `shuntaka9576/dotfiles`, `marcusramberg/nix-config`,
  `berbiche/dotfiles`, `DigitalBrewStudios/darwin-modular-services`
  (shim library, not a config), `astratagem/dotfield`. Shortlist filed
  above: llama-swap FOD models, symbolic hotkeys + ByHost defaults,
  completion cache, backup dead-man's-switch + rclone ordering +
  encrypt_if_changed, service-catalog fan-out, OCI container
  hardening, nvfetcher, nono, thoughtpolice jj revsets (supersedes the
  shikanime entry), gh extensions, direnv config, HM-level sops,
  shellspec + snapshot store-path normalization, gitconfig stragglers,
  CLI shortlist in §6. Lessons noted, not filed: source-NAT defeats
  IP allowlists (dustinlyons ran open for 10 minutes); modular
  services (nixpkgs#372170 / nix-darwin#1765) as a watch item for
  one-definition systemd+launchd services. Skips: clan-core and
  Blueprint (frameworks owning composition), Determinate/Lix (4th–5th
  sightings), LLM-commit-message exfiltration (2nd), NOPASSWD-ALL
  sudo, per-package pinned nixpkgs inputs.
- 2026-09-03 — eight-repo "high-commit authors" round, selected by a
  GitHub sweep (134 active personal repos with nix in the name,
  ranked by commit count; list in the session scratchpad):
  `reckenrode/nixos-configs` (nixpkgs darwin maintainer),
  `jwiegley/nix-config`, `oddlama/nix-config`, `xddxdd/nixos-config`,
  `thiagokokada/nix-configs`, `foo-dogsquared/nixos-config`,
  `barrucadu/nixfiles`, `takeokunn/nixos-configuration`. Shortlist
  filed above: stopRuleset, PQ ssh pinning (2 independent sightings)
  + client baseline, restic hardening/verification trio + restore
  flake app + UptimeRobot reconciler, msmtp fleet mail, generated
  docs site + per-alert runbooks, generated workflows + two-stage
  lock CI + flat-flake, verify-inputs + never-sudo-flake-update,
  travel-ready, last-known-good overlay, HM darwin defaults (Safari)
  + keyboard-AI killers + unfree allowlist + linux-builder logs +
  remote-builder wiring, the takeokunn agent stack +
  CLAUDE_CONFIG_DIR personas, tailnet/DNS as Terraform, §6 package
  batch. Noted, unfiled: oddlama's distributed-config push model,
  eval-time encrypted PII (nix-plugins cost), nix-topology,
  deterministicIds, zoned nftables; barrucadu per-host observability
  + SNS→ntfy pattern, podman pods as systemd units with 127.0.0.1
  port defaults, ~/tmp auto-sweep; xddxdd fleet-patched nixpkgs,
  geo-IP flake input; thiagokokada per-host activation apps,
  restore-backups HM module, release-skew gate (jwiegley);
  foo-dogsquared module-level VM tests, crowdsec. Skips: LT
  mega-helper and category-enable cascades (dendritic wins again),
  impermanence (3rd decline), LSQuarantine=false, nightly
  --recreate-lock-file upgrades, Lix/Determinate (6th sighting).
- 2026-09-03 — Tier-2 round (seven repos, package-emphasis brief) plus
  two research passes: `lovesegfault/nix-config`, `gvolpe/nix-config`,
  `jtojnar/nixfiles`, `heywoodlh/nixos-configs`,
  `LongerHV/nixos-configuration`, `NobbZ/nixos-config`,
  `mrcjkb/nixfiles`; research on AWS/GCP images and on
  apple/container. Filed above: TPM2 unattended disk unlock, BBR+cake,
  SMART monitoring, rrsync receivers, socketfilterfw reconciliation,
  createApp, firejail GUI sandboxing, direnv layout dirs, vmVariant
  test VMs, EC2-builder profile, the aws-image + GCE-refinement
  research blocks, the openhab digest-pin bug, the apple/container
  watch item, jj-for-PRs + gitconfig stragglers, §6 package batch.
  Noted, unfiled: jtojnar's Anubis scraper shield + cargo-sweep user
  timer; heywoodlh's rayhunter/ntfy relay detail and darwin
  sshd-extraConfig gap; mrcjkb's nix-community builder ssh blocks;
  NobbZ's patched-coreutils shape; gvolpe/NobbZ mostly pre-absorbed
  (their genre fully harvested by earlier rounds). Skips: Determinate
  ecosystem (7th), impermanence (4th), nebula (tailscale is settled),
  no-mitigations kernel param, option-cascade frameworks (3rd),
  weakened backup sshd MACs (hmac-sha1 — the anti-pattern of the PQ
  item). Tier-2 bench still unreviewed: chvp, AlexNabokikh, Kidsan,
  CnTeng, kurnevsky, Sciencentistguy, josephst.
- 2026-09-03 — final bench round, ten repos, closing the GitHub
  sweep: chvp, AlexNabokikh, Kidsan (dead mirror — rank candidates by
  `git log`, not the API updated-at), CnTeng, kurnevsky,
  Sciencentistguy, josephst, Weathercold, BrianHicks, DavSanchez.
  Filed above: websocat-ssh/iodine/hans transports, bwrap wrappers,
  torjail, forge host-key pinning, IPQoS none, darwin module test
  suite, stevenblack hosts module, HVF→TCG CI detail, OrbStack
  builder, niks3 OIDC cache, healthchecks LoadCredential refinement,
  phone-push, file-sharing jail, socktainer note, sops rotation
  targets, Cloudflare token plane, fontconfig/UTC server lines, §6
  package batch. Noted, unfiled: kurnevsky `-march=native` helper and
  README ops one-liners; BrianHicks claude plugins-from-package-src
  with eval assertions; AlexNabokikh symbolic-hotkey rebind catalog
  (implementation reference), independent dendritic adoption
  (validation). Yield confirms saturation: three of ten near zero.
  44 personal repos surveyed total; sweep closed.
- 2026-09-15 — `devon-systems/hoenn` (alyraffauf; 6 NixOS hosts + 1
  nix-darwin + 1 system-manager, flake-parts with `import-tree`, comin, sops,
  disko, nixos-facter). Filed above: system-manager for the Debian hosts, the
  three-platform auto-upgrade shape (`operation = "boot"` + StartLimit +
  cksum-hostname stagger), `.sops.yaml` generated from `keys/*.pub`, restic
  `backupPrepareCommand` preconditions, autoScrub derived from
  `config.fileSystems`, docs generated from config with a `--check` CI mode,
  skill evals with `baseline_without_skill`, the typed peer-registry module
  shape, and the AGENTS.md deploy guards. Skips filed in §7:
  Homebrew-on-NixOS, greedyCasks, hermes-agent, LSQuarantine (3rd).
  Validation, not new: `import-tree` plus `deferredModule` options as the
  entire import story (the dendritic pattern again, arrived at
  independently); one skill directory fanned out to
  claude-code/codex/opencode/crush from a single four-line `builtins.path`
  filter (3rd sighting of skills-as-nix-modules, after madmaxieee and
  drupol); nixos-facter; comin. Pre-filtered as already present: the git
  settings block (zdiff3, histogram, colorMoved, `branch.sort`,
  `rerere.autoupdate`, `updateRefs`, `help.autocorrect`),
  `DSDontWrite{Network,USB}Stores`, `NH_FLAKE`, nix `min-free`/`max-free` and
  automatic gc/optimise. Wart worth not copying: `init.defaultBranch = "main"`
  while the repo's real branch, comin's poller and every workflow trigger are
  `master`.
- 2026-09-15 — `devon-systems/sinnoh` (production: 2 NixOS hosts on
  OpenStack, k3s + Flux + CNPG + OpenTofu) and `devon-systems/johto`
  (homelab: a storage/media server, a k3s node, one microVM guest), the two
  companion repos to hoenn. Filed above: the `check-k8s` render-and-validate
  CI step, the SSRF-safe egress NetworkPolicy, `k3s etcd-snapshot save` as a
  `backupPrepareCommand` plus the exclude-what-backs-itself-up rule, CNPG +
  barman-cloud to B2, `enableEmergencyMode = false`, OpenTofu state on B2
  (with its no-locking caveat), the `from=`/`restrict`/`command=` builder key
  lockdown, microVM secrets over a virtiofs `RuntimeDirectory`, the Tailscale
  operator ProxyGroup ingress and its runbook, one-chart-N-values, minimal
  Loki+Alloy, Flux `dependsOn` ordering, stub-zone DNS, the traefik
  query-parameter drop, `sops.templates` with `restartUnits`, and rclone
  buckets as automounted `fileSystems`. Second sightings, not refiled:
  fail2ban recidive jails, SMART monitoring plus its prometheus exporter,
  restic retention trios, nixos-facter, comin. Warts worth not copying:
  `johto/secrets/kubernetes/` is an orphaned directory of still-live
  encrypted secrets for services that moved to sinnoh — nothing references
  it, `.sops.yaml` still re-keys it, and nobody rotated them, which is the
  failure mode a `sops-rekey` that walks `secrets/**` quietly preserves; and
  both repos deploy from `master` while their own git config sets
  `init.defaultBranch = "main"`.
