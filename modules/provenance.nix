# ABOUTME: Build provenance: every system records the git revision that built
# ABOUTME: it, and logging in to a server names the inputs in /etc/motd.
{ inputs, ... }:
let
  rev = inputs.self.rev or inputs.self.dirtyRev or "dirty";
in
{
  # `nixos-version --json` / `darwin-version --json` report the revision.
  flake.modules.nixos.base = {
    system.configurationRevision = rev;
  };
  flake.modules.darwin.base = {
    system.configurationRevision = rev;
  };

  # Login-time provenance on the headless servers (and the images that
  # compose the server aggregate, like GCE).
  flake.modules.nixos.server =
    { config, ... }:
    {
      users.motd = ''
        NixOS ${config.system.nixos.release}, nixpkgs ${inputs.nixpkgs.rev}
        configuration ${rev}
      '';
    };
}
