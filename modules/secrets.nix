# ABOUTME: Puts age on the system path of every NixOS and nix-darwin host, for
# ABOUTME: the encrypted key transfer the secrets/* Makefile targets do.
{ ... }:
let
  # System profile rather than home.packages: `make secrets/restore` unpacks
  # ~/.ssh and ~/.gnupg onto a machine whose user environment doesn't exist
  # yet, so the tool that decrypts the archive has to be there before
  # home-manager has ever run.
  shared =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.age ];
    };
in
{
  flake.modules.nixos.base = shared;
  flake.modules.darwin.base = shared;
}
