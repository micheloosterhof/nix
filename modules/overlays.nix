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
          # gh CLI on stable has bugs.
          inherit (unstable) gh;

          # Want the latest version of this.
          inherit (unstable) claude-code;

          # Ships as fast as claude-code does, and stable is as far behind.
          inherit (unstable) codex;

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
in
{
  flake.modules.nixos.base = shared;
  flake.modules.nixos.container = shared;
  flake.modules.darwin.base = shared;
}
