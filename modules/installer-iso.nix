# ABOUTME: Minimal NixOS installer ISO with the provisioning ssh key authorized
# ABOUTME: for root, so nixos-anywhere (make vm/provision) needs no console steps.
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (inputs.nixpkgs.lib.hasSuffix "linux" system) {
      packages.installer-iso =
        (inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            (
              { lib, ... }:
              {
                # nixos-anywhere connects as root; authorize the same keys/
                # directory the installed systems authorize.
                users.users.root.openssh.authorizedKeys.keyFiles = lib.pipe (builtins.readDir ../keys) [
                  (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".pub" name))
                  (lib.mapAttrsToList (name: _: ../keys/${name}))
                ];
              }
            )
          ];
        }).config.system.build.isoImage;
    };
}
