# ABOUTME: Keep macOS file indexers out of /nix and external volumes: Spotlight
# ABOUTME: indexes neither, fseventsd keeps no /nix log, Finder skips /nix.
{ ... }:
{
  flake.modules.darwin.base = {
    # Spotlight leaves external volumes (USB disks, SD cards, disk images)
    # unindexed instead of crawling each one on mount.
    system.defaults.CustomSystemPreferences."/Library/Preferences/com.apple.SpotlightServer".ExternalVolumesIgnore =
      true;

    # Finder otherwise caches a TFSInfo/_FileCache node per /nix/store entry
    # (~700k objects, ~1GB RSS) when it enumerates the directory.
    system.activationScripts.extraActivation.text = ''
      mkdir -p /nix/.fseventsd
      test -e /nix/.fseventsd/no_log || touch /nix/.fseventsd/no_log
      test -e /nix/.metadata_never_index || touch /nix/.metadata_never_index
      chflags hidden /nix
    '';
  };
}
