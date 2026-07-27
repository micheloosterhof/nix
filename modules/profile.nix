# ABOUTME: Declares the host-shape options (my.profile, my.gui.enable) and turns
# ABOUTME: the profile into capability defaults: a workstation gets a GUI, a server not.
{ ... }:
let
  shared =
    { config, lib, ... }:
    {
      options.my = {
        profile = lib.mkOption {
          type = lib.types.enum [
            "workstation"
            "server"
          ];
          description = "What the host is for. Sets capability defaults.";
        };

        gui.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether the host has a graphical session (Xorg/Wayland). The profile
            sets this by default (workstation on, server off); a host can override
            it, and a hardware platform can force it off with mkForce.
          '';
        };

        tools.full = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether mich's home environment carries the full interactive CLI
            toolkit. On for every host that gets worked on directly, including
            headless pet servers; appliance images (cloud, container) turn it
            off to keep their closures lean.
          '';
        };
      };

      config.my.gui.enable = lib.mkDefault (config.my.profile == "workstation");
    };
in
{
  flake.modules.nixos.base = shared;
  flake.modules.nixos.container = shared;
}
