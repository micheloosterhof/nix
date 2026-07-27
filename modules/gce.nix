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
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        "${inputs.nixpkgs}/nixos/modules/virtualisation/google-compute-config.nix"
        "${inputs.nixpkgs}/nixos/modules/image/repart.nix"
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

      # Secure Boot via a single signed UKI (kernel + initrd + cmdline in one
      # PE binary, so the whole boot path is verified) at the removable UEFI
      # path. The signing key is ephemeral: generated inside the signedUki
      # derivation, discarded with its build directory; only the certificate
      # survives, and `make gce/upload` enrolls it as the image's UEFI
      # PK/KEK/db. Instances launch with --shielded-secure-boot; all three
      # Shielded VM legs (Secure Boot, vTPM, integrity monitoring) work.
      # There is no bootloader and no generation menu: boot changes ship as
      # a new image, not via nixos-rebuild on the instance.
      boot.loader.grub.enable = lib.mkForce false;

      # The image is assembled by systemd-repart directly from the closure —
      # no build VM, no KVM requirement. The root filesystem label matches
      # the fileSystems."/" device set by google-compute-config, and the
      # partition auto-grows to the instance's boot disk on first boot
      # (boot.growPartition + autoResize, also from that profile).
      image.repart = {
        name = "nixos-gce";
        partitions = {
          "10-esp" = {
            contents = {
              "/EFI/BOOT/BOOT${lib.toUpper pkgs.stdenv.hostPlatform.efiArch}.EFI".source =
                "${config.system.build.signedUki}/uki.efi";
            };
            repartConfig = {
              Type = "esp";
              Format = "vfat";
              SizeMinBytes = "512M";
            };
          };
          "20-root" = {
            storePaths = [ config.system.build.toplevel ];
            # repart copies store contents but not the Nix database; ship
            # the closure registration and load it on first boot (below),
            # or every nix operation sees an unregistered store.
            contents."/nix-path-registration".source = "${
              pkgs.closureInfo { rootPaths = [ config.system.build.toplevel ]; }
            }/registration";
            repartConfig = {
              Type = "root";
              Format = "ext4";
              Label = "nixos";
              Minimize = "guess";
            };
          };
        };
      };
      # The filesystem label (not just the GPT label) must be "nixos": the
      # GCE profile mounts / by /dev/disk/by-label/nixos.
      image.repart.mkfsOptions.ext4 = [ "-L nixos" ];

      # First boot: register the baked closure in the Nix database, then
      # drop the file so this runs once.
      boot.postBootCommands = ''
        if [ -f /nix-path-registration ]; then
          ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration &&
            rm -f /nix-path-registration
        fi
      '';

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
      # While OS Login is enabled its PAM account module denies local users,
      # so IAM admins are the working login path and need a sudo binary they
      # can execute: relax hardening.nix's wheel-only restriction here. The
      # baked mich key only works on instances that set the metadata
      # enable-oslogin=FALSE.
      security.sudo.execWheelOnly = lib.mkForce false;

      # Appliance image: only the lean CLI set in the user environment.
      my.tools.full = false;

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

      # The stock UKI (system.build.uki) signed with a keypair that exists
      # only inside this build: the private key is never an output, so it
      # cannot reach the store, the image, or a cache. cert.der is the
      # public certificate for UEFI enrollment at image registration.
      system.build.signedUki =
        pkgs.runCommand "gce-signed-uki"
          {
            nativeBuildInputs = [
              pkgs.openssl
              pkgs.buildPackages.systemdUkify
            ];
          }
          ''
            openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
              -subj "/CN=nixos-gce-secureboot/" \
              -keyout key.pem -out cert.pem
            mkdir -p $out
            ${pkgs.buildPackages.systemdUkify}/lib/systemd/systemd-sbsign sign \
              --private-key key.pem \
              --certificate cert.pem \
              --output $out/uki.efi \
              ${config.system.build.uki}/${config.system.boot.loader.ukiFile}
            openssl x509 -in cert.pem -outform DER -out $out/cert.der
          '';

      # GCE upload format: a tar.gz containing disk.raw, padded to a whole
      # GiB as the images API requires (sparse, so padding is free). The
      # enrollment certificate rides along for make gce/upload.
      system.build.gceImage =
        pkgs.runCommand "gce-image"
          {
            nativeBuildInputs = [ pkgs.gnutar ];
          }
          ''
            mkdir -p $out
            cp --sparse=always \
              ${config.system.build.image}/${config.image.repart.name}.raw disk.raw
            chmod u+w disk.raw
            size=$(stat -Lc %s disk.raw)
            gib=$(( (size + 1073741823) / 1073741824 ))
            truncate -s $(( gib * 1073741824 )) disk.raw
            tar -Sc disk.raw | gzip -3 > \
              "$out/${config.image.repart.name}-${pkgs.stdenv.hostPlatform.system}.raw.tar.gz"
            cp ${config.system.build.signedUki}/cert.der $out/cert.der
          '';

      # system.stateVersion comes from the server aggregate (server.nix); the
      # image always composes it, so it is not repeated here.
    };

  # Exposed as flake lib so the eval tests can assert on the composed image
  # config (it is not a nixosConfiguration).
  flake.lib.gceSystem =
    system:
    inputs.nixpkgs.lib.nixosSystem {
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
    };

  perSystem =
    { system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (inputs.nixpkgs.lib.hasSuffix "linux" system) {
      packages.gce-image = (config.flake.lib.gceSystem system).config.system.build.gceImage;
    };
}
