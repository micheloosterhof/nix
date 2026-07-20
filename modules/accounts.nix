# ABOUTME: Local account policy on VMs and servers: users are declarative
# ABOUTME: (config owns them, passwd doesn't persist) and wheel sudos
# without a password. hardening.nix restricts sudo to wheel members.
{ ... }:
let
  shared = {
    users.mutableUsers = false;
    security.sudo.wheelNeedsPassword = false;
  };
in
{
  flake.modules.nixos.vm = shared;
  flake.modules.nixos.server = shared;
}
