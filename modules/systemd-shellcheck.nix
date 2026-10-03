# ABOUTME: Runs shellcheck on every generated systemd unit script at build
# ABOUTME: time, so a broken ExecStart/script fails the build, not the boot.
#
# On the base aggregate (every NixOS host). Verified 2026-10-03: all five
# hosts build with it on. Not on nixos.container, which was not tested.
{ ... }:
{
  flake.modules.nixos.base = {
    systemd.enableStrictShellChecks = true;
  };
}
