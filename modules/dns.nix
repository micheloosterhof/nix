# ABOUTME: Encrypted DNS on VMs and servers: systemd-resolved with strict
# ABOUTME: DNS-over-TLS to Quad9, ignoring DHCP-provided plaintext resolvers.
{ ... }:
let
  shared = {
    # Resolve over DNS-over-TLS to Quad9 so lookups are encrypted end-to-end
    # (the network path can't read or tamper with them) and malware-filtered.
    # Both addresses are Quad9's filtering resolvers, so filtering persists on
    # failover; strict TLS makes resolution fail closed rather than leak to
    # plaintext. The "#dns.quad9.net" suffix is the TLS certificate name.
    #
    # Static resolvers also mean name resolution never depends on the DHCP
    # server or on tailscale's MagicDNS forwarder: with resolved, tailscale
    # only adds split-DNS routes for the tailnet domain.
    services.resolved = {
      enable = true;
      settings.Resolve = {
        DNSOverTLS = "true";
        # No built-in plaintext Cloudflare/Google fallback.
        FallbackDNS = [ ];
      };
    };
    networking.nameservers = [
      "9.9.9.9#dns.quad9.net"
      "149.112.112.112#dns.quad9.net"
    ];

    # Strict DoT requires every resolver to speak TLS, so stop DHCP from
    # injecting its plain-53 server into resolved.
    networking.dhcpcd.extraConfig = "nohook resolv.conf";
  };
in
{
  flake.modules.nixos.vm = shared;
  flake.modules.nixos.server = shared;
}
