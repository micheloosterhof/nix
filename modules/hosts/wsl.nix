# ABOUTME: The Windows WSL system: a server-profile host on the NixOS-WSL
# ABOUTME: module, command-line only.
{ config, inputs, ... }:
{
  flake.nixosConfigurations.wsl = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.flake.modules.nixos.base

      inputs.nixos-wsl.nixosModules.wsl

      ../../users/mich/nixos.nix

      { my.profile = "server"; }

      {
        wsl = {
          enable = true;
          wslConf.automount.root = "/mnt";
          defaultUser = "mich";
          startMenuLaunchers = true;
        };

        system.stateVersion = "23.05";
      }

      { config._module.args = { inherit inputs; }; }
    ];
  };
}
