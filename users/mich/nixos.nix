{
  pkgs,
  inputs,
  ...
}:

let
  # Every public key in keys/ may ssh into the VMs (one .pub file per client
  # machine; drop a file there to authorize a new one). modules/keys.nix owns
  # the list and throws when it is empty (an unreachable key-only system).
  authorizedKeyFiles = inputs.self.lib.authorizedKeyFiles;
in
{
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
