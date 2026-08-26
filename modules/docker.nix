# ABOUTME: Docker on VMs and servers (dev containers on the VMs, the oci-
# ABOUTME: containers backend on helium).
{ ... }:
let
  shared = {
    virtualisation.docker = {
      enable = true;
      # Weekly prune of stopped containers, unused networks, and (--all)
      # images no container references, so container debris can't slowly
      # eat a small disk.
      autoPrune = {
        enable = true;
        flags = [ "--all" ];
      };
    };
  };
in
{
  flake.modules.nixos.vm = shared;
  flake.modules.nixos.server = shared;
}
