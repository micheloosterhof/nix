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
  oxygen = self.nixosConfigurations.oxygen.config;
  mac = self.darwinConfigurations.neon.config;

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

  # users/mich/nixos.nix is composed into every NixOS host.
  testUserAccount = {
    expr = fusion.users.users.mich.isNormalUser;
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
  # supportedLocales, not defaultLocale: the default of the latter is already
  # en_US.UTF-8, so only the narrowed locale build proves locale.nix applied.
  testVmLocale = {
    expr = fusion.i18n.supportedLocales;
    expected = [ "en_US.UTF-8/UTF-8" ];
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
  testOxygenProfile = {
    expr = oxygen.my.profile;
    expected = "server";
  };
  testOxygenGuiOff = {
    expr = oxygen.my.gui.enable;
    expected = false;
  };
  testServerHardeningApplied = {
    expr = oxygen.boot.kernel.sysctl."kernel.kptr_restrict";
    expected = 2;
  };
  testServerSshKeyOnly = {
    expr = oxygen.services.openssh.settings.PasswordAuthentication;
    expected = false;
  };
  testServerSshNoRootLogin = {
    expr = oxygen.services.openssh.settings.PermitRootLogin;
    expected = "no";
  };

  # oxygen is internet-facing: firewall on, bogon sources dropped, sshd only
  # on the non-standard port (openFirewall follows ports, so 22 is closed),
  # and nothing trusted beyond the tailnet.
  testOxygenFirewallOn = {
    expr = oxygen.networking.firewall.enable;
    expected = true;
  };
  testOxygenBogonsWired = {
    expr = builtins.hasAttr "bogons" oxygen.networking.nftables.tables;
    expected = true;
  };
  testOxygenSshPort = {
    expr = oxygen.services.openssh.ports;
    expected = [ 4444 ];
  };
  testOxygenSshPort22Closed = {
    expr = builtins.elem 22 oxygen.networking.firewall.allowedTCPPorts;
    expected = false;
  };
  # (the firewall module itself trusts loopback)
  testOxygenTrustsOnlyTailnet = {
    expr = lib.subtractLists [
      "lo"
      "tailscale0"
    ] oxygen.networking.firewall.trustedInterfaces;
    expected = [ ];
  };
  testOxygenTorRelay = {
    expr =
      oxygen.services.tor.relay.enable && builtins.elem 9001 oxygen.networking.firewall.allowedTCPPorts;
    expected = true;
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
  testHeliumPlex = {
    expr = helium.services.plex.enable;
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

  # modules/vm.nix: VM DNS is strict DoT to Quad9 with no plaintext fallback
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
