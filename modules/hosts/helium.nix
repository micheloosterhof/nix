# ABOUTME: helium — bare-metal x86_64 headless server (Intel i5-8500T, 32 GB,
# ABOUTME: UEFI, nvme). Clean NixOS install; disko owns the disk layout.
{ config, inputs, ... }:
{
  flake.nixosConfigurations.helium = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.flake.modules.nixos.base
      config.flake.modules.nixos.server
      config.flake.modules.nixos.plex
      config.flake.modules.nixos.openhab

      inputs.disko.nixosModules.disko

      ../../users/mich/nixos.nix

      {
        my.profile = "server";
        networking.hostName = "helium";
        # Onboard NIC.
        networking.interfaces.eno2.useDHCP = true;

        # openHAB discovers devices over multicast (mDNS 5353, SSDP/UPnP 1900)
        # and binds many random UDP ports that can't be enumerated for rules.
        # helium is a home-automation hub on the trusted home LAN, so trust that
        # interface wholesale; the kernel hardening still applies.
        networking.firewall.trustedInterfaces = [ "eno2" ];
      }

      # Hardware (bare-metal Coffee Lake, nvme, UEFI).
      (
        { lib, ... }:
        {
          boot.initrd.availableKernelModules = [
            "xhci_pci"
            "ahci"
            "nvme"
            "usbhid"
            "sd_mod"
          ];
          boot.kernelModules = [ "kvm-intel" ];
          hardware.cpu.intel.updateMicrocode = true;
          hardware.enableRedistributableFirmware = true;

          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;
        }
      )

      # Disk: GPT with a 1 GiB ESP and an ext4 root over the whole nvme.
      {
        disko.devices.disk.main = {
          device = "/dev/nvme0n1";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  extraArgs = [
                    "-n"
                    "ESP"
                  ];
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  extraArgs = [
                    "-L"
                    "nixos"
                  ];
                };
              };
            };
          };
        };
      }

      { config._module.args = { inherit inputs; }; }
    ];
  };
}
