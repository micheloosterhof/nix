# ABOUTME: Local account policy on VMs and servers: users are declarative
# ABOUTME: (config owns them, passwd doesn't persist) and wheel sudos
# without a password. hardening.nix restricts sudo to wheel members.
{ ... }:
let
  shared = {
    users.mutableUsers = false;
    security.sudo.wheelNeedsPassword = false;

    # sudo accepts a signature from the forwarded ssh-agent (pam_rssh,
    # sufficient) against the sshd-managed keys in
    # /etc/ssh/authorized_keys.d/$ruser. Inert while wheelNeedsPassword
    # skips PAM, but staged so dropping NOPASSWD is a one-line change.
    security.pam.rssh.enable = true;
    security.pam.services.sudo.rssh = true;
  };
in
{
  flake.modules.nixos.vm = shared;
  flake.modules.nixos.server = shared;
}
