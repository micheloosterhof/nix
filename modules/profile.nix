# ABOUTME: Declares the host-shape options (my.profile, my.gui.enable, my.exposure,
# ABOUTME: my.tools.full) and turns the profile into capability defaults.
#
# Declared identically on every class, darwin included, so one signal answers
# "what is this host" everywhere and no consumer needs a platform test or an
# `or` fallback to cope with the option being absent.
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

        exposure = lib.mkOption {
          type = lib.types.enum [
            "lan"
            "internet"
          ];
          default = "lan";
          description = ''
            Where the host faces. Gates only those controls whose *correctness*
            depends on network position — not a security tier: hardening,
            key-only ssh and sudo restrictions are unconditional everywhere.
            Bogon source-drops are the case in point: wrong, not merely
            unneeded, where legitimate traffic has RFC1918 sources.

            "lan" is the conservative default, so a host that never says where
            it faces gets no position-dependent rule. The image targets keep it:
            they bake no posture, and a deployment that faces the internet sets
            this beside its other per-deployment config.
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

  flake.modules.darwin.base.imports = [
    shared
    (
      { lib, ... }:
      {
        # my.gui.enable means "this host has a graphical session we manage",
        # which macOS never does — Aqua is not ours to configure. mkForce, so
        # profile = "workstation" cannot default it back on, the same way
        # platforms/apple-vm.nix forces it off on a headless Linux guest.
        my.gui.enable = lib.mkForce false;
      }
    )
  ];
}
