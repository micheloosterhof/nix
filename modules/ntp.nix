# ABOUTME: Time sync on VMs and servers: timesyncd uses NTP servers the
# ABOUTME: network hands out, with time.google.com as the only static fallback.
{ ... }:
let
  shared = {
    services.timesyncd = {
      # No static servers on top of network-provided ones (the nixpkgs
      # default pins the NixOS NTP pool, doubling sources on networks whose
      # DHCP offers NTP). The fallback only answers when no link provides a
      # server.
      servers = [ ];
      fallbackServers = [ "time.google.com" ];
    };
  };
in
{
  flake.modules.nixos.vm = shared;
  flake.modules.nixos.server = shared;
}
