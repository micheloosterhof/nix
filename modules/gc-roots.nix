# ABOUTME: Weekly cleanup of stale Nix GC roots: old auto roots (result
# ABOUTME: symlinks, nix-direnv envs), stale temproots, and broken root links.
{ ... }:
let
  # per-user is deliberately left alone: it holds the profile roots, and an
  # idle machine must not lose the root of its current generation.
  cleanupScript =
    pkgs:
    pkgs.writeShellScript "nix-cleanup-gcroots" ''
      # Auto roots (nix build ./result links, nix-direnv envs) older than 30
      # days; the link mtime refreshes whenever the root is re-registered.
      ${pkgs.findutils}/bin/find /nix/var/nix/gcroots/auto -type l -mtime +30 -delete
      # Stale temproots left behind by crashed nix processes.
      ${pkgs.findutils}/bin/find /nix/var/nix/temproots -type f -mtime +10 -delete
      # Roots whose target is already gone.
      ${pkgs.findutils}/bin/find /nix/var/nix/gcroots -xtype l -delete
    '';
in
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      systemd.timers.nix-cleanup-gcroots = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
        };
      };
      systemd.services.nix-cleanup-gcroots = {
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${cleanupScript pkgs}";
        };
      };
    };

  # Sunday 02:30, half an hour before the scheduled GC (nix-settings.nix), so
  # the roots freed here are collected in the same window.
  flake.modules.darwin.base =
    { pkgs, ... }:
    {
      launchd.daemons.nix-cleanup-gcroots = {
        serviceConfig = {
          ProgramArguments = [ "${cleanupScript pkgs}" ];
          StartCalendarInterval = [
            {
              Weekday = 0;
              Hour = 2;
              Minute = 30;
            }
          ];
        };
      };
    };
}
