# ABOUTME: nitrogen — cloud x86_64 headless server (KVM guest, 1 core, 2 GB,
# ABOUTME: BIOS, virtio). Clean NixOS install; disko owns the disk layout.
{ config, inputs, ... }:
{
  flake.nixosConfigurations.nitrogen = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.flake.modules.nixos.base
      config.flake.modules.nixos.server
      config.flake.modules.nixos.bogons

      inputs.disko.nixosModules.disko

      ../../users/mich/nixos.nix

      {
        my.profile = "server";
        networking.hostName = "nitrogen";
        # Kernel-style names make the single virtio NIC always eth0; predictable
        # naming would call it ens3 and tie the config to the VM's PCI layout —
        # a mismatch after a provider-side change would leave the box with no
        # network.
        networking.usePredictableInterfaceNames = false;
        networking.interfaces.eth0.useDHCP = true;

        # KVM guest agent: lets the provider do graceful shutdown / report the IP.
        services.qemuGuest.enable = true;

        # Non-standard ssh port (openFirewall follows it, so 22 closes).
        # 3333, not 4444: the home ISP silently drops outbound TCP to 4444
        # (verified by on-box tcpdump), which is why oxygen used 3333 too.
        services.openssh.ports = [ 3333 ];

        # Tailscale exit node: tailnet clients can route their internet
        # traffic out through this box. "server" turns on the kernel
        # forwarding sysctls; the set-flag is re-applied by tailscaled-set
        # on every boot. Needs one-time approval in the admin console.
        services.tailscale.useRoutingFeatures = "server";
        services.tailscale.extraSetFlags = [ "--advertise-exit-node" ];
      }

      # Hardware (QEMU/KVM guest, virtio, BIOS). The qemu-guest profile pulls in
      # the virtio initrd modules.
      (
        { modulesPath, ... }:
        {
          imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

          # Serial console so the provider's console/VNC works.
          boot.kernelParams = [
            "console=ttyS0,115200"
            "console=tty1"
          ];

          # Legacy BIOS boot: grub embeds into the disk's BIOS-boot partition.
          # disko wires grub.devices from the EF02 partition, so we only enable it.
          boot.loader.grub = {
            enable = true;
            efiSupport = false;
          };
        }
      )

      # Disk: GPT with a 1 MiB BIOS-boot partition (for grub), 2 GiB swap
      # (only 2 GB RAM), and an ext4 root over the rest.
      {
        disko.devices.disk.main = {
          device = "/dev/vda";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                size = "1M";
                type = "EF02";
              };
              swap = {
                size = "2G";
                content = {
                  type = "swap";
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
