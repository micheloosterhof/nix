# ABOUTME: Shared Nix daemon settings (flakes, registry pin, gc), merged into
# ABOUTME: the base aggregate of every NixOS and nix-darwin host.
{ ... }:
let
  shared =
    {
      inputs,
      pkgs,
      lib,
      ...
    }:
    {
      nix = {
        package = pkgs.nixVersions.latest;

        extraOptions = ''
          experimental-features = nix-command flakes
          keep-outputs = true
          keep-derivations = true
        '';

        settings = {
          # 256 MiB — default 64 MiB fills up during big closure fetches.
          download-buffer-size = 256 * 1024 * 1024;
          # Hard-link identical store paths to save disk as they're added.
          # Linux-only: on macOS this has a history of store corruption
          # (https://github.com/NixOS/nix/issues/7273); the scheduled
          # nix.optimise.automatic below runs `nix store optimise` instead.
          auto-optimise-store = pkgs.stdenv.isLinux;
          # Build derivations in parallel; "auto" = number of logical cores.
          max-jobs = "auto";
          # Use XDG dirs (~/.local/state/nix, ~/.config/nix) instead of the
          # ~/.nix-profile / ~/.nix-defexpr dotfiles.
          use-xdg-base-directories = true;
        };

        # Periodically hard-link identical store paths. On macOS this is the
        # safe alternative to inline auto-optimise-store (see above); on Linux
        # it complements it by catching paths added out-of-band.
        optimise.automatic = true;

        # Resolve <nixpkgs> and nixpkgs#... to the flake's pinned input so no
        # channels are needed and every host builds against the same nixpkgs.
        registry.nixpkgs.flake = inputs.nixpkgs;
        nixPath = [ "nixpkgs=flake:nixpkgs" ];
        channel.enable = false;

        # Collect garbage weekly, keeping the last 30 days of generations.
        # Scheduling differs by platform: darwin (launchd) uses `interval`,
        # NixOS (systemd) uses `dates`.
        gc = {
          automatic = true;
          options = "--delete-older-than 30d";
        }
        // lib.optionalAttrs pkgs.stdenv.isDarwin {
          interval = {
            Weekday = 0;
            Hour = 3;
            Minute = 0;
          };
        }
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          dates = "weekly";
        };
      }
      # Run daemon builds at background/idle priority so long compiles (the
      # Linux builder, from-source packages) never compete with interactive
      # work. The option names differ per platform: launchd process type on
      # darwin, CPU scheduling policy on systemd.
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        daemonProcessType = "Background";
        daemonIOLowPriority = true;
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        daemonCPUSchedPolicy = "idle";
      };
    };
in
{
  flake.modules.nixos.base = shared;
  flake.modules.nixos.container = shared;
  flake.modules.darwin.base = shared;
}
