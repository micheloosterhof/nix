# Pure-eval regression tests for the host composition glue (modules/hosts/
# and the base aggregates in modules/). Each test
# forces a slice of an evaluated host config and compares it to what the
# wiring is supposed to produce: machine/user/home-manager modules imported,
# _module.args propagated, overlays applied. Run via the `eval-tests` flake
# check (nothing is built; failures throw at evaluation time).
{
  self,
  lib,
  inputs,
}:

let
  fusion = self.nixosConfigurations.vm-aarch64-fusion.config;
  utm = self.nixosConfigurations.vm-aarch64-utm.config;
  apple = self.nixosConfigurations.vm-aarch64-apple.config;
  wsl = self.nixosConfigurations.wsl.config;
  helium = self.nixosConfigurations.helium.config;
  nitrogen = self.nixosConfigurations.nitrogen.config;
  mac = self.darwinConfigurations.neon.config;

  gce = (self.lib.gceSystem "x86_64-linux").config;

  homePackageNames = cfg: map (p: p.pname or p.name) cfg.home-manager.users.mich.home.packages;

  # Same import the flake overlay does, so the overlay tests compare the
  # final pkgs against the source of truth rather than a hardcoded version.
  unstable =
    system:
    import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
in
lib.runTests {
  # The vm aggregate is composed into every Linux VM host.
  testFusionHostname = {
    expr = fusion.networking.hostName;
    expected = "dev";
  };
  testUtmHostname = {
    expr = utm.networking.hostName;
    expected = "dev";
  };
  testAppleHostname = {
    expr = apple.networking.hostName;
    expected = "dev";
  };
  testDarwinStateVersion = {
    expr = mac.system.stateVersion;
    expected = 5;
  };

  # modules/hostname-guard.nix: hosts with an explicit hostname refuse to
  # activate on a machine with a different one (wrong-host deploy guard).
  testHostnameGuardServer = {
    expr = lib.hasInfix "nitrogen" (nitrogen.system.preSwitchChecks.hostnameGuard or "");
    expected = true;
  };
  # Anchored on the assignment: a bare "dev" would also match /dev paths.
  testHostnameGuardVm = {
    expr = lib.hasInfix "expected=dev" (fusion.system.preSwitchChecks.hostnameGuard or "");
    expected = true;
  };
  # wsl leaves networking.hostName at its default (WSL owns the hostname),
  # so it must not be guarded.
  testHostnameGuardSkipsUnnamedHost = {
    expr = wsl.system.preSwitchChecks ? hostnameGuard;
    expected = false;
  };
  # The GCE image is generic: instances get their hostname from metadata,
  # so the image must not pin one.
  testHostnameGuardSkipsGce = {
    expr = gce.system.preSwitchChecks ? hostnameGuard;
    expected = false;
  };
  testHostnameGuardDarwin = {
    expr =
      mac.networking.hostName == "neon"
      && lib.hasInfix "hostname guard" mac.system.activationScripts.preActivation.text;
    expected = true;
  };

  # users/mich/nixos.nix is composed into every NixOS host.
  testUserAccount = {
    expr = fusion.users.users.mich.isNormalUser;
    expected = true;
  };

  # The silent-misconfig assertions stay wired: an empty keys/ must refuse to
  # build (ssh is key-only), and the fusion disko labels must match the
  # mounted filesystems. Only the wiring is asserted here; the assertions
  # themselves are enforced when CI builds the toplevels.
  testKeysAssertionWired = {
    expr = lib.any (a: lib.hasInfix "keys/" a.message) nitrogen.assertions;
    expected = true;
  };
  testDiskoLabelAssertionWired = {
    expr = lib.any (a: lib.hasInfix "disko partition labels" a.message) fusion.assertions;
    expected = true;
  };

  # The HM package set is tiered by my.tools.full: interactive hosts —
  # workstations and pet servers alike — carry the full toolkit; appliance
  # images (GCE) carry only the lean CLI set.
  testApplianceHomeLacksFullToolkit = {
    expr = lib.filter (n: lib.elem n (homePackageNames gce)) [
      "hashcat"
      "claude-code"
      "ffmpeg"
    ];
    expected = [ ];
  };
  testApplianceHomeKeepsLeanTools = {
    expr = lib.all (n: lib.elem n (homePackageNames gce)) [
      "ripgrep"
      "htop"
      "jq"
    ];
    expected = true;
  };
  testPetServerKeepsFullToolkit = {
    expr = lib.all (n: lib.elem n (homePackageNames helium)) [
      "hashcat"
      "ast-grep"
    ];
    expected = true;
  };
  testWorkstationHomeKeepsFullToolkit = {
    expr = lib.any (p: (p.pname or p.name) == "hashcat") fusion.home-manager.users.mich.home.packages;
    expected = true;
  };

  # The GCE image boots a single signed UKI from the removable EFI path;
  # no bootloader is installed and the image is assembled with repart.
  testGceNoBootloader = {
    expr = {
      systemdBoot = gce.boot.loader.systemd-boot.enable;
      grub = gce.boot.loader.grub.enable;
    };
    expected = {
      systemdBoot = false;
      grub = false;
    };
  };
  # BOOTX64.EFI is the x86_64 removable path; correct while `gce` above is
  # the x86_64 composition only. An aarch64 assertion would need BOOTAA64.EFI
  # (the image derives it from hostPlatform.efiArch).
  testGceEspCarriesUki = {
    expr = builtins.hasAttr "/EFI/BOOT/BOOTX64.EFI" gce.image.repart.partitions."10-esp".contents;
    expected = true;
  };
  testGceRootPartitionFromClosure = {
    expr =
      gce.image.repart.partitions."20-root".storePaths == [ gce.system.build.toplevel ]
      && gce.image.repart.partitions."20-root".repartConfig.Format == "ext4";
    expected = true;
  };
  testGceImageOutputsExist = {
    expr = (gce.system.build ? signedUki) && (gce.system.build ? gceImage);
    expected = true;
  };
  # OS Login is the image's admin path (PAM denies local users while it is
  # enabled), so IAM admins must be able to execute sudo: the wheel-only
  # sudo binary from hardening.nix is relaxed on this image.
  testGceOsLoginSudo = {
    expr = {
      osLogin = gce.security.googleOsLogin.enable;
      wheelOnly = gce.security.sudo.execWheelOnly;
    };
    expected = {
      osLogin = true;
      wheelOnly = false;
    };
  };

  # The image must carry the closure's store-db registration and load it on
  # first boot; without it every nix operation on the instance sees an
  # unregistered store (HM activation is the first casualty).
  testGceStoreDbRegistration = {
    expr =
      (builtins.hasAttr "/nix-path-registration" gce.image.repart.partitions."20-root".contents)
      && (lib.hasInfix "nix-path-registration" gce.boot.postBootCommands);
    expected = true;
  };

  # The NixOS-WSL module is composed in and configured by the wsl host file.
  testWslEnabled = {
    expr = wsl.wsl.enable;
    expected = true;
  };
  testWslDefaultUser = {
    expr = wsl.wsl.defaultUser;
    expected = "mich";
  };

  # The profile axis: each host file sets my.profile.
  testFusionProfile = {
    expr = fusion.my.profile;
    expected = "workstation";
  };
  testWslProfile = {
    expr = wsl.my.profile;
    expected = "server";
  };

  # Settings shared by the vm and server aggregates (ssh.nix, docker.nix,
  # locale.nix, accounts.nix): asserted on a VM here, on a server below.
  testVmSshKeyOnly = {
    expr = fusion.services.openssh.settings.PasswordAuthentication;
    expected = false;
  };
  testVmDocker = {
    expr = fusion.virtualisation.docker.enable;
    expected = true;
  };
  # The built locale set stays exactly the two locales the settings
  # reference (nixpkgs computes it from defaultLocale + extraLocaleSettings);
  # growth here means some module bloated the glibcLocales build.
  testVmLocale = {
    expr = fusion.i18n.supportedLocales;
    expected = [
      "C.UTF-8/UTF-8"
      "en_US.UTF-8/UTF-8"
    ];
  };
  # LC_TIME diverges from the en_US default so timestamps render 24-hour.
  testVmLcTime24h = {
    expr = fusion.i18n.extraLocaleSettings.LC_TIME;
    expected = "C.UTF-8";
  };
  # LC_ALL overrides every LC_* category (defeating the LC_TIME setting
  # above), so the HM environment must not export it.
  testHmNoLcAll = {
    expr = fusion.home-manager.users.mich.home.sessionVariables ? LC_ALL;
    expected = false;
  };
  # The dotfiles are leading for session env vars (sourced after HM's), so
  # a stray LC_ALL export there would defeat LC_TIME the same way. Lists the
  # offending files on failure. Function-local `local LC_ALL=...` is fine.
  testDotfilesNoLcAll = {
    expr =
      lib.filter
        (
          f:
          let
            text = builtins.readFile (../users/mich + "/${f}");
          in
          lib.hasInfix "export LC_ALL" text || lib.hasInfix "\nLC_ALL=" text
        )
        [
          "bash_env"
          "bash_profile"
          "bashrc"
          "zshenv"
          "zprofile"
          "zshrc"
        ];
    expected = [ ];
  };
  testVmDeclarativeUsers = {
    expr = fusion.users.mutableUsers;
    expected = false;
  };
  testServerDocker = {
    expr = helium.virtualisation.docker.enable;
    expected = true;
  };

  # The server hosts. Both are headless server-profile machines with the
  # kernel hardening applied via the server aggregate and key-only ssh.
  testHeliumProfile = {
    expr = helium.my.profile;
    expected = "server";
  };
  testNitrogenProfile = {
    expr = nitrogen.my.profile;
    expected = "server";
  };
  testNitrogenGuiOff = {
    expr = nitrogen.my.gui.enable;
    expected = false;
  };
  testServerHardeningApplied = {
    expr = nitrogen.boot.kernel.sysctl."kernel.kptr_restrict";
    expected = 2;
  };
  testServerSshKeyOnly = {
    expr = nitrogen.services.openssh.settings.PasswordAuthentication;
    expected = false;
  };
  testServerSshNoRootLogin = {
    expr = nitrogen.services.openssh.settings.PermitRootLogin;
    expected = "no";
  };

  # nitrogen is internet-facing: firewall on, bogon sources dropped, sshd only
  # on the non-standard port (openFirewall follows ports, so 22 is closed),
  # and nothing trusted beyond the tailnet.
  testNitrogenFirewallOn = {
    expr = nitrogen.networking.firewall.enable;
    expected = true;
  };
  testNitrogenBogonsWired = {
    expr = builtins.hasAttr "bogons" nitrogen.networking.nftables.tables;
    expected = true;
  };
  # modules/bogons.nix: the fullbogons lists contain loopback (127/8), CGNAT
  # (100.64/10 — the tailnet), and RFC1918 (the docker bridge) space, so the
  # drop chain must accept local/overlay interfaces first or it silences the
  # resolved stub, all tailnet traffic, and container-to-host traffic.
  testBogonsExemptLocalInterfaces = {
    expr =
      let
        content = nitrogen.networking.nftables.tables.bogons.content;
      in
      lib.hasInfix ''iif "lo" accept'' content
      && lib.hasInfix ''iifname "tailscale0" accept'' content
      && lib.hasInfix ''iifname "docker0" accept'' content;
    expected = true;
  };
  testNitrogenSshPort = {
    expr = nitrogen.services.openssh.ports;
    expected = [ 3333 ];
  };
  testNitrogenSshPort22Closed = {
    expr = builtins.elem 22 nitrogen.networking.firewall.allowedTCPPorts;
    expected = false;
  };
  # (the firewall module itself trusts loopback)
  testNitrogenTrustsOnlyTailnet = {
    expr = lib.subtractLists [
      "lo"
      "tailscale0"
    ] nitrogen.networking.firewall.trustedInterfaces;
    expected = [ ];
  };
  # nitrogen runs no relay/public service: sshd's port is the only inbound
  # opening (via openFirewall); the dropped Tor relay's 9001 is gone.
  testNitrogenNoExtraPorts = {
    expr = nitrogen.networking.firewall.allowedTCPPorts;
    expected = [ 3333 ];
  };
  # Servers resolve over Quad9 DoT via systemd-resolved (modules/dns.nix), so
  # name resolution works without a DHCP-provided or tailscale-forwarded
  # resolver (the datacenter DHCP registered nothing on one boot, and the
  # tailscale 1.98.10 MagicDNS forwarder stopped answering).
  testServerResolvedEnabled = {
    expr = nitrogen.services.resolved.enable;
    expected = true;
  };
  testServerNameservers = {
    expr = nitrogen.networking.nameservers;
    expected = [
      "9.9.9.9#dns.quad9.net"
      "149.112.112.112#dns.quad9.net"
    ];
  };

  # nitrogen is a tailscale exit node: kernel forwarding on (via
  # useRoutingFeatures = "server") and the advertisement applied each boot.
  testNitrogenExitNodeForwarding4 = {
    expr = nitrogen.boot.kernel.sysctl."net.ipv4.conf.all.forwarding";
    expected = true;
  };
  testNitrogenExitNodeForwarding6 = {
    expr = nitrogen.boot.kernel.sysctl."net.ipv6.conf.all.forwarding";
    expected = true;
  };
  testNitrogenExitNodeAdvertised = {
    expr = nitrogen.services.tailscale.extraSetFlags;
    expected = [ "--advertise-exit-node" ];
  };

  # helium sits behind NAT on the trusted home LAN: the onboard NIC is a
  # trusted interface (openHAB multicast discovery), no bogon filtering, and
  # the home-automation services are wired.
  testHeliumTrustsHomeLan = {
    expr = builtins.elem "eno2" helium.networking.firewall.trustedInterfaces;
    expected = true;
  };
  testHeliumNoBogons = {
    expr = builtins.hasAttr "bogons" helium.networking.nftables.tables;
    expected = false;
  };
  # The home-automation services are feature aggregates helium composes.
  testPlexAggregate = {
    expr = self.modules.nixos ? plex;
    expected = true;
  };
  testHeliumPlex = {
    expr = helium.services.plex.enable;
    expected = true;
  };
  testOpenhabAggregate = {
    expr = self.modules.nixos ? openhab;
    expected = true;
  };
  testHeliumOpenhabContainer = {
    expr = helium.virtualisation.oci-containers.containers.openhab.autoStart;
    expected = true;
  };

  # The GUI capability. A workstation gets it by default...
  testFusionGuiEnabled = {
    expr = fusion.my.gui.enable;
    expected = true;
  };
  testFusionXserverEnabled = {
    expr = fusion.services.xserver.enable;
    expected = true;
  };
  # ...but the apple-vm platform forces it off even though the profile is
  # workstation (mkForce beats the profile's mkDefault), and with it Xorg.
  testAppleGuiForcedOff = {
    expr = apple.my.gui.enable;
    expected = false;
  };
  testAppleXserverDisabled = {
    expr = apple.services.xserver.enable;
    expected = false;
  };

  # home-manager is wired up for the right user on both platforms.
  testHmUserLinux = {
    expr = fusion.home-manager.users.mich.home.username;
    expected = "mich";
  };
  testHmUserDarwin = {
    expr = mac.home-manager.users.mich.home.username;
    expected = "mich";
  };
  testHmBackupExtension = {
    expr = fusion.home-manager.backupFileExtension;
    expected = "before-hm";
  };

  # The GUI capability reaches home-manager via osConfig: i3 follows my.gui.enable.
  testFusionHmI3Enabled = {
    expr = fusion.home-manager.users.mich.xsession.windowManager.i3.enable;
    expected = true;
  };
  testAppleHmI3Disabled = {
    expr = apple.home-manager.users.mich.xsession.windowManager.i3.enable;
    expected = false;
  };

  # The flake overlay cherry-picks gh from nixpkgs-unstable; if the overlay
  # is dropped these revert to the stable versions and (usually) diverge.
  testOverlayGhLinux = {
    expr = self.nixosConfigurations.vm-aarch64-fusion.pkgs.gh.version;
    expected = (unstable "aarch64-linux").gh.version;
  };
  testOverlayGhDarwin = {
    expr = self.darwinConfigurations.neon.pkgs.gh.version;
    expected = (unstable "aarch64-darwin").gh.version;
  };

  # The OCI-image output family: the container package evaluates to a
  # buildable derivation.
  testContainerImageIsDrv = {
    expr = lib.isDerivation self.packages.aarch64-linux.container-server;
    expected = true;
  };

  # The GCE image output family: a headless server image builds on both the
  # cloud-default x86_64 and aarch64 (Graviton/Axion).
  testGceImageX86IsDrv = {
    expr = lib.isDerivation self.packages.x86_64-linux.gce-image;
    expected = true;
  };
  testGceImageArmIsDrv = {
    expr = lib.isDerivation self.packages.aarch64-linux.gce-image;
    expected = true;
  };

  # modules/nix-settings.nix: the personal cachix cache is a substituter on
  # every host (CI substitutes the linux-builder image from it for neon).
  testCachixSubstituterNixos = {
    expr = builtins.elem "https://micheloosterhof.cachix.org" fusion.nix.settings.extra-substituters;
    expected = true;
  };
  testCachixSubstituterDarwin = {
    expr = builtins.elem "https://micheloosterhof.cachix.org" mac.nix.settings.extra-substituters;
    expected = true;
  };
  # Substituters stay optional: substitution failure falls back to building.
  testSubstituterFallback = {
    expr = fusion.nix.settings.fallback;
    expected = true;
  };

  # modules/dns.nix: VM DNS is strict DoT to Quad9 with no plaintext fallback
  # (fails closed rather than leaking to the NAT gateway's resolver).
  testVmDnsOverTls = {
    expr = fusion.services.resolved.settings.Resolve.DNSOverTLS;
    expected = "true";
  };
  testVmDnsNoFallback = {
    expr = fusion.services.resolved.settings.Resolve.FallbackDNS;
    expected = [ ];
  };

  # modules/diff.nix: every host prints a closure diff during activation.
  testDiffActivationNixos = {
    expr = lib.hasInfix "diff-closures" fusion.system.activationScripts.diff.text;
    expected = true;
  };
  testDiffActivationDryActivate = {
    expr = fusion.system.activationScripts.diff.supportsDryActivation;
    expected = true;
  };
  testDiffActivationDarwin = {
    expr = lib.hasInfix "diff-closures" mac.system.activationScripts.preActivation.text;
    expected = true;
  };

  # modules/spotlight.nix: macOS indexers are kept out of /nix.
  testSpotlightNixSuppression = {
    expr = lib.hasInfix "metadata_never_index" mac.system.activationScripts.extraActivation.text;
    expected = true;
  };

  # hosts/neon.nix: the Linux builder advertises nixos-test in
  # /etc/nix/machines so VM tests (checks.aarch64-linux.*) are accepted
  # without a per-invocation feature override.
  testLinuxBuilderNixosTest = {
    expr = builtins.elem "nixos-test" (lib.head mac.nix.buildMachines).supportedFeatures;
    expected = true;
  };

  # modules/nix-settings.nix: daemon builds run at background/idle priority
  # so they never compete with interactive work.
  testDaemonQosDarwin = {
    expr = mac.nix.daemonProcessType;
    expected = "Background";
  };
  testDaemonQosNixos = {
    expr = fusion.nix.daemonCPUSchedPolicy;
    expected = "idle";
  };

  # HM eval trims: no manuals, no nixpkgs release check (measurably faster
  # eval on every rebuild).
  testHmNoManpages = {
    expr = mac.home-manager.users.mich.manual.manpages.enable;
    expected = false;
  };
  testHmNoReleaseCheck = {
    expr = mac.home-manager.users.mich.home.enableNixpkgsReleaseCheck;
    expected = false;
  };

  # modules/needs-reboot.nix: switching to a new kernel stack prints advice.
  testNeedsRebootNixos = {
    expr = lib.hasInfix "booted-system" fusion.system.activationScripts.needsReboot.text;
    expected = true;
  };

  # modules/gc-roots.nix: stale gc roots are cleaned up weekly on every host.
  testGcrootsCleanupNixos = {
    expr = fusion.systemd.timers.nix-cleanup-gcroots.timerConfig.OnCalendar;
    expected = "weekly";
  };
  testGcrootsCleanupDarwin = {
    expr =
      (builtins.head mac.launchd.daemons.nix-cleanup-gcroots.serviceConfig.StartCalendarInterval).Hour;
    expected = 2;
  };
}
