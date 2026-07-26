# ABOUTME: Google Compute Engine image: a headless server-profile NixOS image
# ABOUTME: for GCE, plus the packages.<system>.gce-image build (x86_64 + aarch64).
#
# Generic and reusable: hostname and IP come from GCE metadata/DHCP at boot,
# so one image deploys to many instances. The internet-facing posture (bogons,
# tighter rules) is layered per-deployment, not baked — an instance without an
# external IP needs none of it, and the host firewall stays on either way.
{ config, inputs, ... }:
{
  flake.modules.nixos.gce =
    { pkgs, lib, ... }:
    {
      imports = [
        "${inputs.nixpkgs}/nixos/modules/virtualisation/google-compute-image.nix"
      ];

      # Dynamic addressing: DHCP on the single GCE NIC (predictable names are
      # off in the GCE profile, so it's eth0). Per-interface, not the global
      # switch, so it doesn't also try to DHCP docker0/tailscale0 (server.nix
      # keeps the global switch off for that reason).
      networking.interfaces.eth0.useDHCP = true;

      # Keep the host firewall on whether or not a given instance has an
      # external IP; GCP's own network firewall is separate (defense in
      # depth). The GCE profile defaults it off with mkDefault, so this plain
      # assignment wins.
      networking.firewall.enable = true;

      # UEFI boot so the image can run as a Shielded VM (vTPM + integrity
      # monitoring). Registering the image needs the UEFI_COMPATIBLE guest OS
      # feature (make gce/upload adds it). Shielded VM's Secure Boot option
      # additionally needs signed boot components, which stock NixOS doesn't
      # provide — create instances with Secure Boot off until a lanzaboote
      # signing setup exists; vTPM and integrity monitoring work regardless.
      virtualisation.googleComputeImage.efi = true;

      # Explicit image size: the default "auto" sizes the filesystem to the
      # closure plus 512 MiB, which ext4 metadata overhead exceeds at this
      # closure size (~11 GiB), failing the build in cptofs. The root
      # partition grows to the instance's boot disk on first boot.
      virtualisation.diskSize = 16 * 1024;

      # Standard GCP login as a fallback alongside the baked mich key, so a
      # fresh instance is never a lockout and behaves like a normal GCE VM:
      #   - OS Login (security.googleOsLogin, enabled unconditionally by the
      #     GCE profile) is NSS/PAM-based and needs the instance/project
      #     metadata enable-oslogin=TRUE plus IAM roles at deploy time.
      #   - metadata SSH keys, the console SSH button and `gcloud compute ssh`
      #     go through the guest agent's account daemon, which only runs with
      #     mutable users. The fleet is immutable-users by policy
      #     (accounts.nix); this is a deliberate cloud-image-only exception.
      users.mutableUsers = lib.mkForce true;
      # hardening.nix restricts logins to mich; relax it so OS Login and
      # guest-agent users (IAM- or key-gated) can authenticate too.
      services.openssh.settings.AllowUsers = lib.mkForce null;

      # Generic cloud image: containers via podman, not docker. The server
      # aggregate enables docker (for the container-running pet servers);
      # a generic cloud base shouldn't carry the daemon.
      virtualisation.docker.enable = lib.mkForce false;
      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
      };

      # gcloud / gsutil on the instance (base components only, no extras).
      environment.systemPackages = [ pkgs.google-cloud-sdk ];

      # system.stateVersion comes from the server aggregate (server.nix); the
      # image always composes it, so it is not repeated here.
    };

  perSystem =
    { system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (inputs.nixpkgs.lib.hasSuffix "linux" system) {
      packages.gce-image =
        (inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            config.flake.modules.nixos.base
            config.flake.modules.nixos.server
            config.flake.modules.nixos.gce
            ../users/mich/nixos.nix
            { my.profile = "server"; }
            {
              config._module.args = {
                inputs = inputs;
              };
            }
          ];
        }).config.system.build.googleComputeImage;
    };
}
