# ABOUTME: Minimal NixOS installer ISO with the provisioning ssh key authorized
# ABOUTME: for root, so nixos-anywhere (make remote/provision) needs no console steps.
{ config, inputs, ... }:
{
  perSystem =
    { system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (inputs.nixpkgs.lib.hasSuffix "linux" system) {
      packages.installer-iso =
        (inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            {
              # nixos-anywhere connects as root; authorize the same keys/
              # list the installed systems authorize (modules/keys.nix).
              users.users.root.openssh.authorizedKeys.keyFiles = config.flake.lib.authorizedKeyFiles;
            }
          ];
        }).config.system.build.isoImage;
    };
}
