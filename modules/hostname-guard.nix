# ABOUTME: Refuses to activate a configuration on a machine whose hostname
# ABOUTME: differs from the config's, catching wrong-host deploys.
{ lib, ... }:
{
  # Guard only hosts that explicitly name themselves (networking.hostName set
  # below option-default priority). Unnamed hosts (wsl: WSL owns the hostname)
  # and generic images that take an empty hostname from DHCP/metadata (gce)
  # stay unguarded. Wrong-host deploys happen when NIXADDR and NIXNAME (or a
  # defaulted NIXNAME on a local `make rebuild`) disagree.
  flake.modules.nixos.base =
    {
      config,
      options,
      pkgs,
      ...
    }:
    {
      system.preSwitchChecks.hostnameGuard =
        lib.mkIf
          (
            options.networking.hostName.highestPrio < (lib.mkOptionDefault { }).priority
            && config.networking.hostName != ""
          )
          ''
            # An override marker allows an intentional rename ($1/$2 are the
            # new system path and action verb; sudo and systemd-run strip
            # custom environment variables, so a file beats an env var here).
            if [ -e /run/hostname-guard-override ]; then
              exit 0
            fi

            # nixos-install and nixos-anywhere activate in a chroot where the
            # kernel hostname belongs to the installer, not this config.
            if ${pkgs.systemd}/bin/systemd-detect-virt --chroot --quiet; then
              exit 0
            fi

            read -r running < /proc/sys/kernel/hostname
            expected=${lib.escapeShellArg config.networking.hostName}
            if [ "$running" != "$expected" ]; then
              echo "hostname guard: this configuration is for $expected but this machine is '$running'."
              echo "Refusing to activate a wrong-host deploy. For an intentional rename, run:"
              echo "  sudo touch /run/hostname-guard-override"
              exit 1
            fi
          '';
    };

  # Darwin: same guard, in the pre-activation hook (aborts the set -e
  # activation script before any mutation). Applies once networking.hostName
  # is set; the override marker mirrors the NixOS one.
  flake.modules.darwin.base =
    { config, ... }:
    {
      system.activationScripts.preActivation.text = lib.mkIf (config.networking.hostName != null) ''
        if [ ! -e /var/run/hostname-guard-override ]; then
          running=$(/bin/hostname -s)
          expected=${lib.escapeShellArg config.networking.hostName}
          if [ "$running" != "$expected" ]; then
            echo "hostname guard: this configuration is for $expected but this machine is '$running'."
            echo "Refusing to activate a wrong-host deploy. For an intentional rename, run:"
            echo "  sudo touch /var/run/hostname-guard-override"
            exit 2
          fi
        fi
      '';
    };
}
