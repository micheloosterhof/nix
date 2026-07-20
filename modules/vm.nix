# ABOUTME: Headless base for Linux VM guests: boot loader, hostname, DHCP +
# ABOUTME: DoT DNS, open firewall. Carries no graphical stack; gui.nix adds
# that when on. ssh/docker/locale/kernel/accounts are shared feature files.
{ ... }:
{
  flake.modules.nixos.vm =
    { pkgs, ... }:
    {
      # Use the systemd-boot EFI boot loader.
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # /boot is only ~249 MiB. Each generation's kernel + initrd is ~90 MiB on
      # aarch64, so at most two generations fit; cap retained generations to keep
      # the ESP from filling.
      boot.loader.systemd-boot.configurationLimit = 2;

      # Define your hostname.
      networking.hostName = "dev";

      # Set your time zone.
      time.timeZone = "Asia/Singapore";

      # Global DHCP: pick up any interface that appears. Hypervisor NICs get
      # unpredictable enpXsY names, so we don't hardcode one.
      networking.useDHCP = true;

      # Resolve over DNS-over-TLS to Quad9 so lookups are encrypted end-to-end
      # (the ISP and the NAT can't read or tamper with them) and malware-filtered.
      # Both addresses are Quad9's filtering resolvers, so filtering persists on
      # failover; strict TLS makes resolution fail closed rather than leak to
      # plaintext. The "#dns.quad9.net" suffix is the TLS certificate name.
      services.resolved = {
        enable = true;
        settings.Resolve = {
          DNSOverTLS = "true";
          # No built-in plaintext Cloudflare/Google fallback.
          FallbackDNS = [ ];
        };
      };
      networking.nameservers = [
        "9.9.9.9#dns.quad9.net"
        "149.112.112.112#dns.quad9.net"
      ];

      # Strict DoT requires every resolver to speak TLS, so stop DHCP from
      # injecting the NAT gateway's plain-53 server into resolved.
      networking.dhcpcd.extraConfig = "nohook resolv.conf";

      # Default is [ perl rsync strace ]. We don't need perl; keep the rest.
      environment.defaultPackages = with pkgs; [
        rsync
        strace
      ];

      # List packages installed in system profile. To search, run:
      # $ nix search wget
      # Linux system-level packages only. Cross-platform CLI tools belong in
      # home.packages (users/mich/home-manager.nix); macOS GUI apps and
      # brew-only formulae belong in users/mich/darwin.nix homebrew.
      environment.systemPackages = with pkgs; [
        gcc
        gnumake
        killall
        vim
      ];

      # Disable the firewall since we're in a VM and we want to make it
      # easy to visit stuff in here. We only use NAT networking anyways.
      networking.firewall.enable = false;

      # This value determines the NixOS release from which the default
      # settings for stateful data, like file locations and database versions
      # on your system were taken. It‘s perfectly fine and recommended to leave
      # this value at the release version of the first install of this system.
      # Before changing this value read the documentation for this option
      # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
      system.stateVersion = "20.09"; # Did you read the comment?
    };
}
