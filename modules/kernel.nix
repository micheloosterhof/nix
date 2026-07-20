# ABOUTME: Latest kernel on VMs and servers. Be careful updating this.
{ ... }:
let
  shared =
    { pkgs, ... }:
    {
      boot.kernelPackages = pkgs.linuxPackages_latest;
    };
in
{
  flake.modules.nixos.vm = shared;
  flake.modules.nixos.server = shared;
}
