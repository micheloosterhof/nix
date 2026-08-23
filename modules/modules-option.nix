# ABOUTME: Declares flake.modules.<class>.<name>: named aggregates of NixOS /
# ABOUTME: nix-darwin modules that feature files merge into and hosts compose from.
{ lib, ... }:
{
  options.flake.modules = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.deferredModule);
    default = { };
    description = ''
      Lower-level modules keyed by class (nixos, darwin) and name. Multiple
      files defining the same name merge into one module (deferredModule).
    '';
  };

  # flake-parts declares no flake.lib option, so without this a second file
  # defining a flake.lib.<name> entry conflicts with the first (raw values
  # merge as `unique`).
  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = ''
      Flake-level library values, one entry per feature file (gceSystem,
      authorizedKeyFiles). Entries merge; redefining one entry conflicts.
    '';
  };
}
