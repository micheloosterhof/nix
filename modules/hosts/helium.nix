# ABOUTME: helium — bare-metal x86_64 headless server (Intel i5-8500T, 32 GB,
# ABOUTME: UEFI, nvme). Clean NixOS install; disko owns the disk layout.
{ config, inputs, ... }:
{
  flake.nixosConfigurations.helium = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.flake.modules.nixos.base
      config.flake.modules.nixos.server

      inputs.disko.nixosModules.disko

      ../../users/mich/nixos.nix

      {
        my.profile = "server";
        networking.hostName = "helium";
        # Onboard NIC.
        networking.interfaces.eno2.useDHCP = true;
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

      # Services: Plex media server + openHAB home automation.
      {
        # Plex is unfree.
        nixpkgs.config.allowUnfree = true;

        services.plex = {
          enable = true;
          openFirewall = true;
        };

        # openHAB isn't packaged in nixpkgs, so run the official image via the
        # docker backend (enabled in server.nix). Host networking lets it
        # auto-discover devices (UPnP/mDNS/KNX); its data lives under
        # /var/lib/openhab (restore the old install's conf/userdata there).
        # TODO: pin to a specific version/digest instead of latest.
        virtualisation.oci-containers = {
          backend = "docker";
          containers.openhab = {
            image = "openhab/openhab:latest";
            autoStart = true;
            extraOptions = [
              "--net=host"
              "--tty"
            ];
            volumes = [
              "/var/lib/openhab/conf:/openhab/conf"
              "/var/lib/openhab/userdata:/openhab/userdata"
              "/var/lib/openhab/addons:/openhab/addons"
              "/etc/localtime:/etc/localtime:ro"
            ];
            environment = {
              OPENHAB_HTTP_PORT = "8080";
              OPENHAB_HTTPS_PORT = "8443";
            };
          };
        };

        # openHAB runs with host networking, so open its UI ports on the host
        # (also reachable over tailscale, which this doesn't cover per-interface).
        networking.firewall.allowedTCPPorts = [
          8080
          8443
        ];

        # openHAB discovers devices over multicast (mDNS 5353, SSDP/UPnP 1900)
        # and binds many random UDP ports that can't be enumerated for rules.
        # helium is a home-automation hub on the trusted home LAN, so trust that
        # interface wholesale; the kernel hardening still applies.
        networking.firewall.trustedInterfaces = [ "eno2" ];
      }

      { config._module.args = { inherit inputs; }; }
    ];
  };
}
