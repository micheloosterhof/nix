# ABOUTME: The Apple Virtualization.framework guest ("container machine"): a
# ABOUTME: workstation-profile VM whose platform forces the GUI off (headless).
{ config, inputs, ... }:
{
  flake.nixosConfigurations.vm-aarch64-apple = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      config.flake.modules.nixos.base
      config.flake.modules.nixos.vm
      config.flake.modules.nixos.apple-vm

      ../../users/mich/nixos.nix

      { my.profile = "workstation"; }

      {
        networking.hostName = "dev-apple";
        my.hostnameGuard = true;
      }

      # Instance hardware. Hand-authored (no nixos-generate-config run);
      # verify on first boot.
      (
        { lib, ... }:
        {
          # virtio transport for disk, network, console and entropy under
          # Virtualization.framework.
          boot.initrd.availableKernelModules = [
            "virtio_pci"
            "virtio_blk"
            "virtio_net"
            "virtio_console"
            "virtio_rng"
          ];
          boot.initrd.kernelModules = [ ];
          boot.kernelModules = [ ];
          boot.extraModulePackages = [ ];

          fileSystems."/" = lib.mkDefault {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };

          fileSystems."/boot" = lib.mkDefault {
            device = "/dev/disk/by-label/boot";
            fsType = "vfat";
          };

          swapDevices = [ ];
        }
      )

      { config._module.args = { inherit inputs; }; }
    ];
  };
}
