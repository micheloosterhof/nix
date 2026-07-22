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
    { pkgs, ... }:
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

      # gcloud / gsutil on the instance.
      environment.systemPackages = [ pkgs.google-cloud-sdk ];

      # New artifact family: no pre-existing state to preserve.
      system.stateVersion = "26.05";
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
