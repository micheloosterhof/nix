# ABOUTME: Plex media server: the service with its firewall ports opened,
# ABOUTME: exposed as the flake.modules.nixos.plex aggregate for hosts to compose.
{ ... }:
{
  flake.modules.nixos.plex = {
    # Plex is unfree.
    nixpkgs.config.allowUnfree = true;

    services.plex = {
      enable = true;
      openFirewall = true;
    };
  };
}
