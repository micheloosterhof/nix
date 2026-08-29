# ABOUTME: Trims NixOS's environment.defaultPackages ([ perl rsync strace ])
# ABOUTME: on every host: nothing on these systems needs a system-path perl.
{ ... }:
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      # rsync stays: remote/copy pushes the repo onto hosts via `sudo rsync`.
      environment.defaultPackages = with pkgs; [
        rsync
        strace
      ];
    };
}
