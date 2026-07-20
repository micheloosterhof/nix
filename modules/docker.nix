# ABOUTME: Docker on VMs and servers (dev containers on the VMs, the oci-
# ABOUTME: containers backend on helium).
{ ... }:
let
  shared = {
    virtualisation.docker.enable = true;
  };
in
{
  flake.modules.nixos.vm = shared;
  flake.modules.nixos.server = shared;
}
