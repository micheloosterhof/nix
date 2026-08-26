# ABOUTME: Tailscale on every NixOS host (VMs and servers). macOS gets it from
# ABOUTME: the tailscale-app homebrew cask instead. Authenticate with `tailscale up`.
{ ... }:
{
  flake.modules.nixos.base = {
    services.tailscale.enable = true;

    # Trust the tailnet: our own authenticated devices reach any service over
    # tailscale without per-port firewall holes, while the public/LAN side stays
    # firewalled. (No-op on the VMs, whose firewall is off.)
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
  };
}
