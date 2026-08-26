# ABOUTME: Keeps the channel-backed command-not-found handler off on every
# ABOUTME: NixOS host: its database comes from channels, which flakes never fill.
{ ... }:
{
  # Upstream already defaults this off while nix channels are disabled;
  # declared explicitly so neither side of that coupling can silently
  # bring the broken handler back.
  flake.modules.nixos.base.programs.command-not-found.enable = false;
}
