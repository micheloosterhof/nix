# ABOUTME: Trial of Rex (superlogical terminal multiplexer): mich's personal
# ABOUTME: Rex server as a user service, reachable as its own tailnet node.
{ inputs, ... }:
{
  flake.modules.nixos.rex = {
    # The user service stops at logout without linger, ending every session.
    users.users.mich.linger = true;

    home-manager.users.mich = {
      imports = [ inputs.rex.homeManagerModules.default ];

      # Also enables programs.rex: the rex command, its terminfo entry in
      # ~/.terminfo, and the ssh guard in ~/.ssh/config.
      services.rex.enable = true;

      # The server runs its own tsnet node, independent of tailscaled. With no
      # auth key, the first start prints a sign-in link (`rex server status`,
      # `journalctl --user -u rex`); after that, only the account that
      # enrolled the node may connect.
      services.rex.tailscale = {
        enable = true;
        hostname = "rex-dev";
      };
    };
  };
}
