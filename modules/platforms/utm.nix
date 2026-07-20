# ABOUTME: UTM/QEMU guest platform: under GUI, the SPICE agent and software GL
# ABOUTME: fallback (no hardware acceleration in UTM yet).
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

        # For now, we need this since hardware acceleration does not work.
        environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";
      })
    ];
}
