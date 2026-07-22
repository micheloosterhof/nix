# ABOUTME: openHAB home automation, exposed as the flake.modules.nixos.openhab
# ABOUTME: aggregate for hosts to compose.
{ ... }:
{
  flake.modules.nixos.openhab = {
    # openHAB isn't packaged in nixpkgs, so run the official image via the
    # docker backend (enabled in server.nix). Host networking lets it
    # auto-discover devices (UPnP/mDNS/KNX); its data lives under
    # /var/lib/openhab (restore the old install's conf/userdata there).
    # TODO: pin to a specific version/digest instead of latest.
    virtualisation.oci-containers = {
      backend = "docker";
      containers.openhab = {
        image = "openhab/openhab:latest";
        autoStart = true;
        extraOptions = [
          "--net=host"
          "--tty"
        ];
        volumes = [
          "/var/lib/openhab/conf:/openhab/conf"
          "/var/lib/openhab/userdata:/openhab/userdata"
          "/var/lib/openhab/addons:/openhab/addons"
          "/etc/localtime:/etc/localtime:ro"
        ];
        environment = {
          OPENHAB_HTTP_PORT = "8080";
          OPENHAB_HTTPS_PORT = "8443";
        };
      };
    };

    # openHAB runs with host networking, so open its UI ports on the host
    # (also reachable over tailscale, which this doesn't cover per-interface).
    networking.firewall.allowedTCPPorts = [
      8080
      8443
    ];
  };
}
