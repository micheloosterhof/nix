# ABOUTME: Keep macOS file indexers out of /nix: Spotlight never indexes it,
# ABOUTME: fseventsd keeps no log, and Finder doesn't enumerate it.
{ ... }:
{
  flake.modules.darwin.base = {
    # Finder otherwise caches a TFSInfo/_FileCache node per /nix/store entry
    # (~700k objects, ~1GB RSS) when it enumerates the directory.
    system.activationScripts.extraActivation.text = ''
      mkdir -p /nix/.fseventsd
      test -e /nix/.fseventsd/no_log || touch /nix/.fseventsd/no_log
      test -e /nix/.metadata_never_index || touch /nix/.metadata_never_index
      chflags hidden /nix
      # The marker file above is legacy and current macOS mostly ignores it;
      # mdutil is the supported switch. Harmless if already off.
      mdutil -i off /nix >/dev/null 2>&1 || true
    '';
  };
}
