# ABOUTME: Every workaround the fleet carries for a defect or gap outside this
# ABOUTME: repo, in one file so the ones that outlive their cause stay visible.
{ inputs, ... }:
let
  # Packages taken from nixpkgs-unstable because the stable release is
  # unusable, not because the newest version is wanted; each goes away when
  # stable catches up. The deliberate always-latest pins stay in overlays.nix.
  unstablePins =
    { ... }:
    {
      nixpkgs.overlays = [
        (
          _final: prev:
          let
            unstable = import inputs.nixpkgs-unstable {
              system = prev.stdenv.hostPlatform.system;
              config.allowUnfree = true;
            };
          in
          {
            # gh CLI on stable has bugs.
            inherit (unstable) gh;

            # Stable's zed is far behind (1.3.x) and old builds fail to launch
            # against current GPU/library stacks.
            inherit (unstable) zed-editor;

            # Stable's golink release embeds a 2023-era tsnet client that the
            # tailscale console flags as outdated.
            inherit (unstable) golink;
          }
        )
      ];
    };

  # Hard-linking identical store paths as they are added has a history of
  # store corruption on macOS (https://github.com/NixOS/nix/issues/7273), so
  # the setting is Linux-only and the scheduled nix.optimise.automatic in
  # nix-settings.nix runs `nix store optimise` there instead.
  autoOptimiseStore =
    { pkgs, ... }:
    {
      nix.settings.auto-optimise-store = pkgs.stdenv.isLinux;
    };

  # jj cannot read the experimental reftable format (git 2.45+), so new repos
  # stay on the classic loose-refs layout.
  gitRefFormat = {
    home-manager.users.mich.programs.git.settings.init.defaultRefFormat = "files";
  };

  # The user should already exist on the Mac; this lets nix-darwin know what
  # the home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  # Note: nix-darwin only manages the login shell for users listed in
  # users.knownUsers, so don't set `shell` here — it'd be a silent no-op.
  # Change the login shell with chsh instead.
  darwinHomeDirectory = {
    users.users.mich.home = "/Users/mich";
  };
in
{
  flake.modules.nixos.base.imports = [
    unstablePins
    autoOptimiseStore
    gitRefFormat
  ];

  # Containers carry no home-manager, so there is no git config to correct.
  flake.modules.nixos.container.imports = [
    unstablePins
    autoOptimiseStore
  ];

  flake.modules.darwin.base.imports = [
    unstablePins
    autoOptimiseStore
    gitRefFormat
    darwinHomeDirectory
  ];

  # UTM offers the guest no hardware acceleration, so GL renders in software.
  flake.modules.nixos.utm =
    { config, lib, ... }:
    {
      config = lib.mkIf config.my.gui.enable {
        environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";
      };
    };

  # Apple's `container` runtime has no nix expression here: it is installed
  # from Apple's signed pkg into /usr/local/bin, with update-container.sh and
  # uninstall-container.sh next to the binary, because nixpkgs trails upstream
  # far enough to sit behind its security fixes (2026-09-23: 0.12.3 on 26.05,
  # 1.1.0 on unstable, 1.4.1 upstream). It moves into home.packages once
  # nixpkgs tracks the releases.
}
