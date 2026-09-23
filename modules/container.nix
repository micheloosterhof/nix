# ABOUTME: NixOS as a container image: a root-filesystem tarball and an OCI
# ABOUTME: archive, built from the same profile axis as the hosts.
#
# Two outputs from one system. container-server is
# config.system.build.tarball from upstream's docker-container profile:
# import it with `docker import result/tarball/*.tar.xz <name>` (or `podman
# import`), then run/orchestrate with `/init` as the command.
# container-server-oci is an OCI-layout archive with `/init` already baked in
# as the command, for runtimes that load images rather than import root
# filesystems: `container image load -i result` then `container run`.
#
# container-server is deliberately a bare base: no user account, no ssh, no
# services. Workloads and user config get layered on next.
#
# The tarball builds to a correct rootfs (verified: contains /init, activate and
# the nix store). Only the runtime is unvalidated: running systemd as PID 1 in a
# container needs cgroup/privilege setup that can't be exercised from here.
{ config, inputs, ... }:
{
  flake.modules.nixos.container =
    { lib, ... }:
    {
      # A container is headless by definition, whatever the profile default says.
      my.gui.enable = lib.mkForce false;

      # The host runtime owns the container's network, so netfilter is not
      # this system's to program: iptables gets NOPERMISSION.
      networking.firewall.enable = lib.mkForce false;

      # The runtime writes /etc/resolv.conf itself, and resolvconf cannot set
      # ACLs on its state directory here.
      networking.resolvconf.enable = false;

      # The channel the docker-container profile registers lives outside the
      # image closure, so registering it at boot cannot succeed.
      systemd.services.nix-channel-init.enable = false;

      # The release this artifact family first shipped with. New containers have
      # no pre-existing state, so they start at the current release rather than
      # inheriting the VMs' 2020-era install date.
      system.stateVersion = "26.05";
    };

  # Exposed as flake lib so the eval tests can assert on the composed image
  # config (it is not a nixosConfiguration).
  flake.lib.containerSystem =
    system:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        # Upstream's container base: boot.isContainer, minimal profile, /init
        # symlink handling and system.build.tarball.
        "${inputs.nixpkgs}/nixos/modules/profiles/docker-container.nix"
        config.flake.modules.nixos.container
        { my.profile = "server"; }
        { config._module.args = { inherit inputs; }; }
      ];
    };

  perSystem =
    { system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (inputs.nixpkgs.lib.hasSuffix "linux" system) (
      let
        containerSystem = config.flake.lib.containerSystem system;
        inherit (containerSystem) pkgs;
        inherit (containerSystem.config.system.build) toplevel;

        # dockerTools emits a Docker archive; the OCI archive below is the
        # conversion of it, so this one is not a package of its own.
        dockerArchive = pkgs.dockerTools.buildLayeredImage {
          name = "container-server";
          tag = "latest";
          contents = [ toplevel ];
          config.Cmd = [ "${toplevel}/init" ];
          # The system closure brings /etc in as a store symlink, but the
          # runtime writes resolv.conf there before handing over to /init,
          # and NixOS activation builds the real /etc at boot anyway. Swap it
          # for a directory, along with the mount points a container needs --
          # the same preparation upstream's tarball does.
          extraCommands = ''
            rm etc
            mkdir -p proc sys dev etc
          '';
        };
      in
      {
        packages.container-server = containerSystem.config.system.build.tarball;

        packages.container-server-oci =
          pkgs.runCommand "container-server-oci" { nativeBuildInputs = [ pkgs.skopeo ]; }
            ''
              # skopeo puts its scratch space in /var/tmp, which the build
              # sandbox does not have, so point it at the build directory.
              skopeo --insecure-policy --tmpdir "$NIX_BUILD_TOP" \
                copy docker-archive:${dockerArchive} \
                oci-archive:$out:container-server:latest
            '';
      }
    );
}
