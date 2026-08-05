{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # Every public key in keys/ may ssh into the VMs (one .pub file per client
  # machine; drop a file there to authorize a new one). The files must be
  # git-tracked or the flake won't see them.
  authorizedKeyFiles = lib.pipe (builtins.readDir ../../keys) [
    (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".pub" name))
    (lib.mapAttrsToList (name: _: ../../keys/${name}))
  ];
in
{
  # sshd is key-only, so a host built with an empty key list is unreachable.
  # The realistic trap: keys/ files that were never `git add`ed are invisible
  # to the flake and silently drop out of the list.
  assertions = [
    {
      assertion = authorizedKeyFiles != [ ];
      message = "keys/ contains no *.pub files in the flake source (untracked files are invisible); refusing to build an unreachable key-only system.";
    }
  ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  users.users.mich = {
    isNormalUser = true;
    home = "/home/mich";
    extraGroups = [
      "docker"
      "wheel"
    ];
    shell = pkgs.bash;
    hashedPassword = "$y$j9T$XYLI8K6dN63ULBXuoqX0H/$WZpoiBJtwzPV6sEXsCJ3wvReXyIpc2G1d8A4rtvJlh7";
    openssh.authorizedKeys.keyFiles = authorizedKeyFiles;
  };

  # No password: root never logs in directly (sshd has PermitRootLogin=no,
  # mich has passwordless sudo). The keys are kept for provisioning
  # (nixos-anywhere connects as root). Previously this reused mich's hash,
  # which doubled the exposure of a single hash committed to a public repo.
  users.users."root" = {
    openssh.authorizedKeys.keyFiles = authorizedKeyFiles;
  };
}
