# ABOUTME: The UTM/QEMU development VM: a workstation on the utm platform, plus
# ABOUTME: this instance's disks and filesystems.
{ config, inputs, ... }:
{
  flake.nixosConfigurations.vm-aarch64-utm = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      config.flake.modules.nixos.base
      config.flake.modules.nixos.vm
      config.flake.modules.nixos.utm

      ../../users/mich/nixos.nix

      { my.profile = "workstation"; }

      # Instance hardware (originally nixos-generate-config output).
      (
        { modulesPath, ... }:
        {
          imports = [
            (modulesPath + "/profiles/qemu-guest.nix")
          ];

          boot.initrd.availableKernelModules = [
            "xhci_pci"
            "uhci_hcd"
            "virtio_pci"
            "usbhid"
            "usb_storage"
            "sr_mod"
          ];
          boot.initrd.kernelModules = [ ];
          boot.kernelModules = [ ];
          boot.extraModulePackages = [ ];

          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };

          fileSystems."/boot" = {
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
