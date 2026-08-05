# ABOUTME: The VMware Fusion development VM: a workstation on the fusion
# ABOUTME: platform, plus this instance's disks and filesystems.
{ config, inputs, ... }:
let
  # Partition labels: written by disko when provisioning, referenced by the
  # mounted filesystems (the vmware-image module defines the fstab entries).
  # The assertion below keeps the two sides in agreement.
  espLabel = "ESP";
  rootLabel = "nixos";
in
{
  flake.nixosConfigurations.vm-aarch64-fusion = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      config.flake.modules.nixos.base
      config.flake.modules.nixos.vm
      config.flake.modules.nixos.fusion

      # Exposes system.build.vmwareImage. Upstreamed into nixpkgs in 25.05;
      # was previously imported via nixos-generators.
      "${inputs.nixpkgs}/nixos/modules/virtualisation/vmware-image.nix"

      ../../users/mich/nixos.nix

      { my.profile = "workstation"; }

      # Declarative disk layout, consumed by nixos-anywhere when provisioning
      # a fresh VM (make remote/provision). enableConfig = false: the running
      # system keeps mounting by the labels below (the vmware-image module
      # defines the fstab entries); disko only partitions and formats, with
      # matching labels, so a disko-provisioned disk and an image-stamped
      # disk are interchangeable.
      inputs.disko.nixosModules.disko
      {
        disko.enableConfig = false;
        disko.devices.disk.main = {
          type = "disk";
          device = "/dev/nvme0n1";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                # 1 GiB: the default 256 MiB ESP only holds two aarch64
                # generations' kernel + initrd (~90 MiB each).
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  extraArgs = [
                    "-n"
                    espLabel
                  ];
                  mountpoint = "/boot";
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  extraArgs = [
                    "-L"
                    rootLabel
                  ];
                  mountpoint = "/";
                };
              };
            };
          };
        };
      }

      # Instance hardware (originally nixos-generate-config output).
      (
        { lib, ... }:
        {
          boot.initrd.availableKernelModules = [
            "uhci_hcd"
            "ahci"
            "xhci_pci"
            "nvme"
            "usbhid"
            "sr_mod"
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

      # A disko-provisioned disk carries the labels above, so the running
      # system must mount by exactly those labels — otherwise a provisioned
      # VM boots with /boot (or /) unmounted and rebuilds write kernels
      # nowhere.
      (
        { config, ... }:
        {
          assertions = [
            {
              assertion =
                config.fileSystems."/".device == "/dev/disk/by-label/${rootLabel}"
                && config.fileSystems."/boot".device == "/dev/disk/by-label/${espLabel}";
              message = "vm-aarch64-fusion: fileSystems mount labels diverge from the disko partition labels (${rootLabel}/${espLabel}).";
            }
          ];
        }
      )

      { config._module.args = { inherit inputs; }; }
    ];
  };
}
