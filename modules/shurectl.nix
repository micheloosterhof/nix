# ABOUTME: Wires packages/shurectl.nix into the Mac's package set (the mic is
# ABOUTME: on neon) and exposes it as `nix build .#shurectl` on darwin systems.
{ inputs, ... }:
{
  flake.modules.darwin.base.nixpkgs.overlays = [
    (final: _prev: { shurectl = final.callPackage ../packages/shurectl.nix { }; })
  ];

  perSystem =
    { pkgs, system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (inputs.nixpkgs.lib.hasSuffix "darwin" system) {
      packages.shurectl = pkgs.callPackage ../packages/shurectl.nix { };
    };
}
