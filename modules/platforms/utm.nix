# ABOUTME: UTM/QEMU guest platform: unsupported-system packages, and the SPICE
# ABOUTME: agent under GUI for host/guest clipboard and display resizing.
{ ... }:
{
  flake.modules.nixos.utm =
    { config, lib, ... }:
    lib.mkMerge [
      {
        # Lots of stuff that uses aarch64 that claims doesn't work, but actually works.
        nixpkgs.config.allowUnsupportedSystem = true;
      }

      (lib.mkIf config.my.gui.enable {
        # Qemu
        services.spice-vdagentd.enable = true;
      })
    ];
}
