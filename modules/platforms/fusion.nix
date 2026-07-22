# ABOUTME: VMware Fusion guest platform: guest tools, disk-image build and the
# ABOUTME: host<->guest clipboard + sway boot option (the latter only under GUI).
{ ... }:
{
  flake.modules.nixos.fusion =
    {
      config,
      pkgs,
      lib,
      inputs,
      ...
    }:
    let
      user = "mich";

      # Cmd (delivered as Super once Fusion's key mappings are off) -> Ctrl for
      # copy/cut/paste in GUI apps, but NOT in the terminal, where Ctrl+C/V keep
      # their shell meaning and Ghostty handles super+c itself.
      xremapConfig = pkgs.writeText "xremap-config.yml" ''
        keymap:
          - name: cmd-style clipboard for GUI apps
            application:
              not:
                - com.mitchellh.ghostty
            remap:
              Super-c: Ctrl-c
              Super-v: Ctrl-v
              Super-x: Ctrl-x
      '';

      # sway port of xcwd: the focused window's newest child process (its shell)
      # tells us the directory the user is working in, so new terminals open
      # there; falls back to $HOME when there is no usable focused window.
      # via: https://www.reddit.com/r/swaywm/comments/ayedi1/opening_terminals_at_the_same_directory/ei7i1dl/
      windowcwd = pkgs.writeShellScript "windowcwd" ''
        pid=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq '.. | select(.type?) | select(.type=="con") | select(.focused==true).pid')
        ppid=$(${pkgs.procps}/bin/pgrep --newest --parent "$pid")
        ${pkgs.coreutils}/bin/readlink "/proc/$ppid/cwd" || echo "$HOME"
      '';

      swayConfig = pkgs.writeText "sway-config" ''
        set $mod Mod4
        set $term ${pkgs.ghostty}/bin/ghostty
        set $menu ${pkgs.rofi}/bin/rofi -show drun -show-icons

        # The X11 desktop runs dpi 220 (~2x), so scale the Wayland output to match.
        output * scale 2

        bindsym $mod+Return exec $term --working-directory="$(${windowcwd})"
        bindsym $mod+d exec $menu
        bindsym $mod+q kill
        bindsym $mod+Shift+e exec swaymsg exit

        # Workspaces 1-9 plus 0 -> 10, mirroring the i3 layout.
        ${lib.concatMapStringsSep "\n" (n: ''
          bindsym $mod+${toString n} workspace number ${toString n}
        '') (lib.range 1 9)}
        bindsym $mod+0 workspace number 10

        # Per-app Cmd->Ctrl clipboard translation (the whole point of this test).
        exec ${pkgs.xremap}/bin/xremap --watch ${xremapConfig}

        # Host<->guest clipboard via clipway's Wayland backend for open-vm-tools
        # (patched in through the overlay below). The vmusr daemon speaks VMware's
        # copy/paste GuestRPC and drives the Wayland clipboard with wl-copy/wl-paste,
        # so it needs no X11/XWayland. wl-clipboard is on PATH via systemPackages;
        # WAYLAND_DISPLAY comes from the sway env.
        #
        # This inline exec is the minimal wiring. clipway also ships a
        # services.clipway.enable module that supervises the same daemon as a
        # systemd --user service (auto-restart, tracks clipway's launch contract).
        # Adopting it needs a standalone sway-session.target plus importing
        # WAYLAND_DISPLAY into the user systemd environment. Worth revisiting if
        # sway becomes the default session rather than an experiment.
        exec ${pkgs.open-vm-tools}/bin/vmtoolsd -n vmusr

        bar {
          position bottom
          status_command ${pkgs.i3status}/bin/i3status
        }
      '';

      # Hardware cursors are unreliable under the vmwgfx virtual GPU; allow a
      # software renderer fallback so the session always comes up for the test.
      # GTK4's GL/Vulkan renderer crashes on the vmwgfx Wayland EGL ("Error
      # flushing display: Broken pipe"), so force GTK widget rendering to Cairo;
      # apps keep their own GL contexts (e.g. Ghostty's terminal stays accelerated).
      swaySession = pkgs.writeShellScript "sway-session" ''
        export WLR_NO_HARDWARE_CURSORS=1
        export WLR_RENDERER_ALLOW_SOFTWARE=1
        export GSK_RENDERER=cairo
        exec ${pkgs.sway}/bin/sway --config ${swayConfig}
      '';
    in
    lib.mkMerge [
      {
        # Setup qemu so we can run x86_64 binaries
        boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

        # Lots of stuff that uses aarch64 that claims doesn't work, but actually works.
        nixpkgs.config.allowUnsupportedSystem = true;

        # This works through our custom module imported above
        virtualisation.vmware.guest.enable = true;

        # Size of the generated VMDK base image in MiB. Default "auto" sizes
        # to the closure + small headroom, which fills up quickly during
        # iterative nixos-rebuilds. 80 GiB gives comfortable margin.
        vmware.baseImageSize = 80 * 1024;

        # The upstream vmware-image module builds the ESP with make-disk-image's
        # default bootSize of 256 MiB, which only holds two generations' kernel +
        # initrd (~90 MiB each) on aarch64. Rebuild the image with a 1 GiB ESP so
        # /boot has comfortable room. There is no NixOS option for bootSize, so we
        # re-declare the image derivation. Only affects freshly built VMDKs; an
        # existing VM keeps its original partitioning.
        system.build.vmwareImage = lib.mkForce (
          import "${pkgs.path}/nixos/lib/make-disk-image.nix" {
            inherit config lib pkgs;
            name = config.vmware.vmDerivationName;
            baseName = config.image.baseName;
            postVM = ''
              ${pkgs.vmTools.qemu}/bin/qemu-img convert -f raw \
                -o compat6=${
                  if config.vmware.vmCompat6 then "on" else "off"
                },subformat=${config.vmware.vmSubformat} \
                -O vmdk $diskImage $out/${config.image.fileName}
              rm $diskImage
            '';
            format = "raw";
            diskSize = config.virtualisation.diskSize;
            partitionTableType = "efi";
            bootSize = "1024M";
          }
        );

        # VMware firmware only supports console mode 0; otherwise the boot loader
        # prints "error switching console mode" on boot.
        boot.loader.systemd-boot.consoleMode = "0";

        # Share our host filesystem. nofail so a VM without the Fusion shared
        # folder configured still boots (otherwise systemd treats .host:/ as a
        # required mount, fails it, and drops to emergency mode).
        fileSystems."/host" = {
          fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
          device = ".host:/";
          options = [
            "umask=22"
            "uid=1000"
            "gid=1000"
            "allow_other"
            "auto_unmount"
            "defaults"
            "nofail"
          ];
        };
      }

      (lib.mkIf config.my.gui.enable {
        # Patch open-vm-tools with clipway's Wayland clipboard backend so the sway
        # boot option gets host<->guest copy/paste. The overlay is idempotent and
        # additive (it keeps the X11 backend), so the base i3/X11 desktop is
        # unaffected. Note: the patch is pinned to open-vm-tools 13.0.5; a nixpkgs
        # bump past that version may need clipway to rebase.
        nixpkgs.overlays = [ inputs.clipway.overlays.default ];

        # Needed for the VMware user-tools clipboard to work.
        environment.systemPackages = [ pkgs.gtkmm3 ];

        # vmware-user provides clipboard/drag-drop and Fusion window-resize
        # forwarding to the X server. The vmware-guest module's own sessionCommands
        # entry doesn't reliably merge with the shared one under lightdm autologin,
        # so invoke it directly.
        services.xserver.displayManager.sessionCommands = ''
          /run/wrappers/bin/vmware-user-suid-wrapper
        '';

        specialisation.sway.configuration = {
          system.nixos.tags = [ "sway" ];

          # Swap the parent's X11/i3/lightdm desktop for Wayland/sway via greetd.
          services.xserver.enable = lib.mkForce false;
          services.xserver.displayManager.lightdm.enable = lib.mkForce false;
          services.displayManager.autoLogin.enable = lib.mkForce false;

          programs.sway = {
            enable = true;
            wrapperFeatures.gtk = true;
          };

          # Autologin straight into the sway session.
          services.greetd = {
            enable = true;
            settings.default_session = {
              command = "${swaySession}";
              inherit user;
            };
          };

          environment.systemPackages = with pkgs; [
            wl-clipboard # wl-copy / wl-paste for the clipboard test
            rofi
            grim
            slurp
          ];
        };
      })
    ];
}
