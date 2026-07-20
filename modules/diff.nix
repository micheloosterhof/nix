# ABOUTME: Print `nix store diff-closures` between the running system and the
# ABOUTME: one being activated, so every switch shows exactly what changes.
{ ... }:
let
  diffCommand =
    { config, lib, ... }:
    ''
      if [ -e /run/current-system ]; then
        ${lib.getExe config.nix.package} store diff-closures /run/current-system "$systemConfig"
      fi
    '';
in
{
  # NixOS runs every activationScripts entry; supportsDryActivation also shows
  # the diff on `nixos-rebuild dry-activate`.
  flake.modules.nixos.base = args: {
    system.activationScripts.diff = {
      supportsDryActivation = true;
      text = diffCommand args;
    };
  };

  # nix-darwin only runs its fixed set of hooks; preActivation shows the diff
  # before the system is changed.
  flake.modules.darwin.base = args: {
    system.activationScripts.preActivation.text = diffCommand args;
  };
}
