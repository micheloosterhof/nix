# ABOUTME: Secrets for every host via sops-nix: encrypted files in secrets/,
# ABOUTME: decrypted at activation with the host's SSH host key as age identity.
#
# Recipients (.sops.yaml): each host's ed25519 host key (ssh-to-age), plus
# Michel's Secure Enclave identity on neon (age-plugin-se, Touch ID) for
# editing. YubiKey recovery recipients join via `sops updatekeys` when
# provisioned. CI never decrypts — encrypted files evaluate fine.
{ inputs, ... }:
let
  # The host's existing SSH key is the age identity: zero extra key material
  # to provision or back up per machine.
  hostKeyIdentity = {
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  # System profile rather than home.packages: `make secrets/restore` unpacks
  # ~/.ssh and ~/.gnupg onto a machine whose user environment doesn't exist
  # yet, so the tool that decrypts the archive has to be there before
  # home-manager has ever run.
  packages =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        age
        sops
        ssh-to-age
      ];
    };
in
{
  flake.modules.nixos.base = {
    imports = [
      inputs.sops-nix.nixosModules.sops
      hostKeyIdentity
      packages
    ];
  };
  flake.modules.darwin.base = {
    imports = [
      inputs.sops-nix.darwinModules.sops
      hostKeyIdentity
      packages
      # Editing happens on the Mac: the Secure Enclave plugin must be on PATH
      # for sops to encrypt to / decrypt with the age1se recipient, and the
      # fido2 plugin for recovery decryption with the YubiKeys (keys/*.identity).
      (
        { pkgs, ... }:
        {
          environment.systemPackages = [
            pkgs.age-plugin-se
            pkgs.age-plugin-fido2-hmac
          ];
        }
      )
    ];
  };
}
