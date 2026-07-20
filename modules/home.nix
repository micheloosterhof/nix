# ABOUTME: Wires home-manager into every host and loads mich's home
# ABOUTME: configuration, on both NixOS and nix-darwin.
{ inputs, ... }:
let
  settings = {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    # Rename existing dotfiles instead of refusing to overwrite them.
    # First activation moves e.g. ~/.bashrc to ~/.bashrc.before-hm.
    home-manager.backupFileExtension = "before-hm";
  };
  mich = {
    home-manager.users.mich = import ../users/mich/home-manager.nix {
      inherit inputs;
    };
  };
in
{
  flake.modules.nixos.base.imports = [
    inputs.home-manager.nixosModules.home-manager
    settings
    mich
  ];
  flake.modules.darwin.base.imports = [
    inputs.home-manager.darwinModules.home-manager
    settings
    mich
  ];
}
