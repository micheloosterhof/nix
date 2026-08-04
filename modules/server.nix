# ABOUTME: Base for bare-metal and cloud NixOS servers (non-VM): UTC time,
# ABOUTME: per-host networking. Composed by the helium/nitrogen hosts.
# ssh/docker/locale/kernel/accounts are shared feature files; tailscale is
# on the shared base.
{ ... }:
{
  flake.modules.nixos.server =
    { pkgs, lib, ... }:
    {
      # Servers keep UTC; localize in the log/app layer.
      time.timeZone = "UTC";

      # DHCP is configured per host on the real interface, so don't let the
      # global switch bring up docker0/tailscale0 etc.
      networking.useDHCP = lib.mkDefault false;

      environment.systemPackages = with pkgs; [
        git
        vim
        curl
        gnumake
        killall
      ];

      # First-install release for this server family.
      system.stateVersion = "26.05";
    };
}
