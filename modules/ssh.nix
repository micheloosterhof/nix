# ABOUTME: Key-only OpenSSH on VMs and servers: no passwords, no root login.
# ABOUTME: keys/ authorizes mich + root (users/mich/nixos.nix); tailscale
# exposes sshd to the whole tailnet, so key-only matters even where the
# firewall is off (the VMs). hardening.nix adds further sshd restrictions.
{ ... }:
let
  shared = {
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
      settings.PermitRootLogin = "no";
    };
  };
in
{
  flake.modules.nixos.vm = shared;
  flake.modules.nixos.server = shared;
}
