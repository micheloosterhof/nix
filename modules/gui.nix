# ABOUTME: The graphical session (Xorg + i3 + lightdm autologin) plus its fonts,
# ABOUTME: portals and input plumbing. Active only when my.gui.enable is set.
{ ... }:
{
  flake.modules.nixos.base =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    lib.mkIf config.my.gui.enable {
      # Parent system desktop: i3 with autologin. Specialisations (e.g. the sway
      # boot option on Fusion) override this when activated from the boot menu.
      services.xserver = {
        enable = true;

        # modesetting drives the SVGA3D GPU with glamor acceleration. Pin the list
        # so Xorg doesn't probe the abandoned xf86-video-fbdev fallback, which fails
        # to load against current Xorg ("undefined symbol: fbdevHWSave").
        videoDrivers = [ "modesetting" ];

        xkb.layout = "us";
        dpi = 220;

        desktopManager = {
          xterm.enable = false;
          wallpaper.mode = "fill";
        };

        displayManager.sessionCommands = ''
          ${pkgs.xset}/bin/xset r rate 200 40
        '';

        windowManager.i3 = {
          enable = true;
          extraPackages = with pkgs; [
            dmenu # application launcher most people use
          ];
        };
      };

      services.displayManager.defaultSession = lib.mkDefault "none+i3";
      services.displayManager.autoLogin = {
        enable = true;
        user = "mich";
      };
      services.xserver.displayManager.lightdm = {
        enable = lib.mkDefault true;
        greeter.enable = false;
      };

      # uinput + group membership so xremap (used by the sway boot option) can read
      # input devices and create a virtual one.
      hardware.uinput.enable = true;
      users.users.mich.extraGroups = [
        "input"
        "uinput"
      ];

      # The terminal font stack: JetBrains Mono for text, the symbols-only Nerd
      # Font for the powerline/devicon glyphs it lacks, and JuliaMono for the
      # runes and circled digits neither covers. Ghostty names all three
      # (users/mich/home-manager.nix), so a missing one shows up as tofu or as
      # a proportional fallback that overruns the cell.
      fonts = {
        fontDir.enable = true;

        packages = [
          pkgs.fira-code
          pkgs.jetbrains-mono
          pkgs.julia-mono
          pkgs.nerd-fonts.symbols-only
        ];
      };

      environment.systemPackages = with pkgs; [
        xclip

        # For hypervisors that support auto-resizing, this script forces it.
        # I've noticed not everyone listens to the udev events so this is a hack.
        (writeShellScriptBin "xrandr-auto" ''
          xrandr --output Virtual-1 --auto
        '')
      ];

      # Enable flatpak. I don't use any flatpak apps but I do sometimes
      # test them so I keep this enabled.
      services.flatpak.enable = true;
      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        config.common.default = "*";
      };
    };
}
