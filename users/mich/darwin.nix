{ pkgs, ... }:

{
  # The user should already exist on the Mac; this lets nix-darwin know
  # what the home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  # Note: nix-darwin only manages the login shell for users listed in
  # users.knownUsers, so don't set `shell` here — it'd be a silent no-op.
  # Change the login shell with chsh instead.
  users.users.mich = {
    home = "/Users/mich";
  };

  system.primaryUser = "mich";

  # Caps Lock acts as Control.
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  system.defaults = {
    # Disable smart quote/dash substitution (mangles code and config).
    NSGlobalDomain = {
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      # Save new documents to local disk, not iCloud, by default.
      NSDocumentSaveNewDocumentsToCloud = false;
      # Force 24-hour clock display regardless of region.
      AppleICUForce24HourTime = true;
      # Default save and print dialogs to their expanded layout.
      NSNavPanelExpandedStateForSaveMode = true;
      PMPrintingExpandedStateForPrint = true;
    };

    # Menu-bar clock is a separate domain; AppleICUForce24HourTime does not
    # drive it. Show 24-hour time without AM/PM.
    menuExtraClock = {
      Show24Hour = true;
      ShowAMPM = false;
    };

    # Finder: show all extensions + hidden files, path/status bars, list view.
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv";
      _FXSortFoldersFirst = true;
      FXDefaultSearchScope = "SCcf"; # search current folder, not whole Mac
      _FXShowPosixPathInTitle = true;
    };

    # Warning banner shown on the login window.
    loginwindow.LoginwindowText = "Unauthorized access to this machine is prohibited.  Use of this system is limited to authorized individuals only.  All activity is monitored.";

    # No drop shadow around captured windows.
    screencapture.disable-shadow = true;

    # Auto-install minor macOS updates (point releases). Major version
    # upgrades stay manual; no key here triggers them.
    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;

    # English UI with Netherlands region formatting (metric, DD-MM-YYYY,
    # Monday-start weeks), currency shown in SGD. Set via CustomUserPreferences
    # because nix-darwin has no typed NSGlobalDomain.AppleLocale option.
    CustomUserPreferences.NSGlobalDomain.AppleLocale = "en_NL@currency=SGD";

    # Don't litter .DS_Store files on network shares or USB volumes.
    CustomUserPreferences."com.apple.desktopservices" = {
      DSDontWriteNetworkStores = true;
      DSDontWriteUSBStores = true;
    };

    # Quit the printer app automatically once print jobs finish.
    CustomUserPreferences."com.apple.print.PrintingPrefs"."Quit When Finished" = true;

    # Check for, download, and install minor + security updates automatically.
    CustomUserPreferences."com.apple.SoftwareUpdate" = {
      AutomaticCheckEnabled = true;
      AutomaticDownload = true;
      CriticalUpdateInstall = true;
      ConfigDataInstall = true;
    };
  };

  fonts.packages = [
    pkgs.atkinson-hyperlegible
    pkgs.atkinson-hyperlegible-next
    pkgs.atkinson-hyperlegible-mono
    pkgs.b612
    pkgs.jetbrains-mono
    pkgs.julia-mono
    pkgs.nerd-fonts.symbols-only
  ];

  # Snapshot of `brew leaves` / `brew list --cask` / `brew tap` on 2026-05-11.
  #
  # onActivation.cleanup controls what darwin-rebuild does with brew state
  # not declared here:
  #   "none"      -- only install missing items; leave everything else alone.
  #                  Ad-hoc `brew install` survives. (current setting)
  #   "uninstall" -- declarative-strict; anything not listed is uninstalled.
  #                  Flip to this once the lists below are exhaustive.
  #   "zap"       -- like "uninstall" but also deletes config/data dirs.
  homebrew = {
    enable = true;
    onActivation.cleanup = "none";

    taps = [
      "hashicorp/tap"
    ];

    brews = [
      "mas"
    ];

    masApps = {
      "Apple Configurator" = 1037126344;
      "OmniFocus" = 1346203938;
      "TestFlight" = 899247664;
      "Windows App" = 1295203466;
      "Xcode" = 497799835;
    };

    casks = [
      "bitwarden"
      "blackhole-2ch"
      "bruno"
      "calibre"
      "chromium"
      "db-browser-for-sqlite"
      "discord"
      "docker-desktop"
      "firefox"
      "ghostty"
      "google-chrome"
      "google-drive"
      "hashicorp-vagrant"
      "logitech-camera-settings"
      "maltego"
      "obs"
      "plex"
      "plex-media-server"
      "secretive"
      "signal"
      "slack"
      "spotify"
      "steam"
      "tailscale-app"
      "visual-studio-code"
      "vlc"
      "whatcable"
      "whatsapp"
      "wireshark-app"
      "yubico-authenticator"
      "zoom"
      "zotero"
    ];
  };

  # Outside this manifest: Apple's `container` CLI (one lightweight VM per
  # container) is installed from its signed pkg into /usr/local/bin; manage
  # it with the update-container.sh / uninstall-container.sh scripts there.
  # No brew cask exists, and nixpkgs ships it as `container` but lags
  # upstream (0.12.3 vs 1.0.0 pkg, 2026-06) — move it into home.packages
  # once nixpkgs catches up.

  # Symlink the nix JDK into the system JavaVirtualMachines directory so
  # /usr/bin/java and Java-aware GUI apps (Maltego) discover it via
  # java_home. Maltego requires JDK 21: its launcher passes
  # -Djava.security.manager=allow, which JDK 24+ rejects at startup
  # (JEP 486 removed the Security Manager). Trader Workstation needs none
  # of this: it bundles its own install4j JRE.
  system.activationScripts.postActivation.text = ''
    mkdir -p /Library/Java/JavaVirtualMachines
    ln -sfn ${pkgs.openjdk}/Library/Java/JavaVirtualMachines/zulu-21.jdk \
      /Library/Java/JavaVirtualMachines/zulu-21.jdk
  '';
}
