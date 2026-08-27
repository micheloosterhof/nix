# ABOUTME: golink (go/name short links, tailscale/golink): joins the tailnet as
# ABOUTME: its own node via tsnet, exposed as flake.modules.nixos.golink.
{ ... }:
{
  flake.modules.nixos.golink =
    { pkgs, ... }:
    {
      # No vhost, cert, or firewall hole: tsnet dials out to the tailnet and
      # serves only on the node's tailscale address (as hostname "go").
      systemd.services.golink = {
        description = "golink tailnet short-link service";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.golink}/bin/golink --sqlitedb /var/lib/golink/golink.db --config-dir /var/lib/golink/tsnet";
          DynamicUser = true;
          StateDirectory = "golink";
          Restart = "on-failure";
          # First start only: TS_AUTHKEY joins the tailnet non-interactively.
          # Optional (-) because after that the tsnet state dir carries the node
          # identity; without the file the first start logs a login URL instead.
          EnvironmentFile = "-/etc/golink/tailscale-authkey.env";
        };
      };
    };
}
