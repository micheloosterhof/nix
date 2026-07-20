# ABOUTME: Turns off all on-system documentation (man/info/doc and the NixOS
# ABOUTME: manual) on every NixOS host and container.
#
# Two reasons. Size: the docs add ~700 MB to an image. Churn: the NixOS
# manual derivation depends on the entire nixos/ module tree, so unrelated
# nixpkgs changes rebuild the system just to regenerate docs
# (https://mastodon.online/@nomeata/109915786344697931).
#
# All five lines are needed: documentation.enable is NOT a master switch —
# man.enable (default true) takes effect independently of it, so dropping
# the sub-options would silently install man-db.
{ ... }:
let
  shared = {
    documentation = {
      enable = false;
      man.enable = false;
      doc.enable = false;
      info.enable = false;
      nixos.enable = false;
    };
  };
in
{
  flake.modules.nixos.base = shared;
  flake.modules.nixos.container = shared;
}
