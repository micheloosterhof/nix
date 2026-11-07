# ABOUTME: Trial of Rex (superlogical terminal multiplexer): mich's personal
# ABOUTME: Rex server on dev as a tailnet node, and the rex CLI on neon.
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

  # On macOS the Rex app runs the server; this puts the rex command on PATH,
  # e.g. `rex -S rex-dev.<tailnet>.ts.net ls` to reach dev.
  flake.modules.darwin.rex = {
    home-manager.users.mich = {
      imports = [ inputs.rex.homeManagerModules.default ];
      programs.rex.enable = true;
    };
  };
}
