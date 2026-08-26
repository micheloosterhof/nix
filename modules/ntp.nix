# ABOUTME: Time sync on VMs and servers: timesyncd uses NTP servers the
# ABOUTME: network hands out, falling back to the regular NixOS pool.
{ ... }:
let
  shared =
    { config, ... }:
    {
      services.timesyncd = {
        # No static servers on top of network-provided ones (the nixpkgs
        # default pins the pool as primary, doubling sources on networks
        # whose DHCP offers NTP). DHCP-offered servers only reach timesyncd
        # through networkd's UseNTP; on hosts still running scripted DHCP
        # the fallback pool answers everywhere.
        servers = [ ];
        fallbackServers = config.networking.timeServers;
      };
    };
in
{
  flake.modules.nixos.vm = shared;
  flake.modules.nixos.server = shared;
}
