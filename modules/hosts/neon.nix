# ABOUTME: neon — the MacBook Pro M1 nix-darwin system: Touch ID sudo, the
# ABOUTME: Linux builder, and macOS shell integration.
{ config, inputs, ... }:
{
  flake.darwinConfigurations.neon = inputs.darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [
      config.flake.modules.darwin.base

      ../../users/mich/darwin.nix

      (
        { pkgs, ... }:
        {
          # Set in Sept 2024 as part of the macOS Sequoia release.
          system.stateVersion = 5;

          # The machine's name, enforced by nix-darwin and checked by the
          # hostname guard (modules/hostname-guard.nix).
          networking.hostName = "neon";

          # Match the nixbld gid used by the upstream nixos.org installer (30000).
          # nix-darwin's default is 350, which would trip its gid-mismatch assertion.
          ids.gids.nixbld = 30000;

          # We use proprietary software on this machine
          nixpkgs.config.allowUnfree = true;

          # Authenticate sudo with TouchID (falls back to password if no finger).
          # reattach=true wires in pam_reattach so Touch ID also prompts when sudo
          # is run from inside tmux/screen (those detach from the GUI bootstrap).
          security.pam.services.sudo_local = {
            touchIdAuth = true;
            reattach = true;
          };

          # Shared Nix settings (package, flakes, registry pin) live in
          # modules/nix-settings.nix. Below are the darwin-only bits.
          nix = {
            enable = true;

            # Enable the Linux builder so we can run Linux builds on our Mac.
            # This can be debugged by running `sudo ssh linux-builder`.
            #
            # The customizations below make the builder cache-miss against
            # cache.nixos.org, so the first activation must use the default
            # (un-customized) variant; only after a working builder exists can
            # this customized image be built.
            linux-builder = {
              enable = true;
              ephemeral = true;
              maxJobs = 8;
              # The defaults plus nixos-test, so NixOS VM tests
              # (checks.aarch64-linux.*) are accepted without a per-invocation
              # feature override. The M1 has no nested virtualization, so
              # those tests run under qemu TCG: correct, just slow.
              supportedFeatures = [
                "kvm"
                "benchmark"
                "big-parallel"
                "nixos-test"
              ];
              config = (
                { pkgs, ... }:
                {
                  virtualisation = {
                    cores = 8;
                    darwin-builder = {
                      diskSize = 100 * 1024; # 100GB
                      memorySize = 32 * 1024; # 32GB
                    };
                  };
                  environment.systemPackages = [
                    pkgs.htop
                  ];
                }
              );
            };

            settings = {
              # Required for the linux builder
              trusted-users = [ "@admin" ];
            };
          };

          # zsh is the default shell on Mac and we want to make sure that we're
          # configuring the rc correctly with nix-darwin paths.
          programs.zsh.enable = true;
          programs.zsh.shellInit = ''
            # Nix
            if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
              . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
            fi
            # End Nix

            # nix-darwin does not add the per-user Nix profile to PATH; do it here.
            if [ -d "/etc/profiles/per-user/$USER/bin" ]; then
              export PATH="/etc/profiles/per-user/$USER/bin:$PATH"
            fi
          '';

          environment.shells = with pkgs; [
            bashInteractive
            zsh
          ];
        }
      )

      { config._module.args = { inherit inputs; }; }
    ];
  };
}
