# ABOUTME: Pins selected packages to nixpkgs-unstable via an overlay applied to
# ABOUTME: every NixOS and nix-darwin host.
{ inputs, ... }:
let
  shared = {
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
          # Want the latest version of this.
          inherit (unstable) claude-code;

          # Ships as fast as claude-code does, and stable is as far behind.
          inherit (unstable) codex;
        }
      )
    ];
  };
in
{
  flake.modules.nixos.base = shared;
  flake.modules.nixos.container = shared;
  flake.modules.darwin.base = shared;
}
