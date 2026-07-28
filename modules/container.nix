# ABOUTME: NixOS as a container root-filesystem tarball: one OCI artifact for
# ABOUTME: docker/podman/k8s/apple, built from the same profile axis as the hosts.
#
# The output is config.system.build.tarball from upstream's docker-container
# profile: import it with `docker import result/tarball/*.tar.xz <name>` (or
# `podman import`), then run/orchestrate with `/init` as the command. A baked
# entrypoint OCI wrapper on top is a possible follow-up.
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

      # The release this artifact family first shipped with. New containers have
      # no pre-existing state, so they start at the current release rather than
      # inheriting the VMs' 2020-era install date.
      system.stateVersion = "26.05";
    };

  perSystem =
    { system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (inputs.nixpkgs.lib.hasSuffix "linux" system) {
      packages.container-server =
        (inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            # Upstream's container base: boot.isContainer, minimal profile, /init
            # symlink handling and system.build.tarball.
            "${inputs.nixpkgs}/nixos/modules/profiles/docker-container.nix"
            config.flake.modules.nixos.container
            { my.profile = "server"; }
            { config._module.args = { inherit inputs; }; }
          ];
        }).config.system.build.tarball;
    };
}
