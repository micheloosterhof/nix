# ABOUTME: Exposes the keys/ *.pub files as flake.lib.authorizedKeyFiles, the
# ABOUTME: one list every ssh-authorization site (hosts, installer ISO) reads.
#
# sshd is key-only everywhere, so a system built from an empty list is
# unreachable. The realistic trap: keys/ files that were never `git add`ed are
# invisible to the flake and silently drop out — hence the throw rather than a
# per-consumer assertion, so no consumer can forget the guard.
{ lib, ... }:
{
  flake.lib.authorizedKeyFiles =
    let
      files = lib.pipe (builtins.readDir ../keys) [
        (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".pub" name))
        (lib.mapAttrsToList (name: _: ../keys/${name}))
      ];
    in
    if files == [ ] then
      throw "keys/ contains no *.pub files in the flake source (untracked files are invisible); refusing to build an unreachable key-only system."
    else
      files;
}
