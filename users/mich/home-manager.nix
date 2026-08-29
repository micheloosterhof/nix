{ inputs, ... }:

{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # A graphical session exists only on a Linux host whose system config turns
  # the GUI capability on. `or false` keeps this safe on darwin where the
  # my.gui option isn't defined.
  gui = isLinux && (osConfig.my.gui.enable or false);

  # Appliance images get the lean CLI set only; every host worked on
  # directly — workstations and headless pet servers alike — carries the
  # full toolkit. `or true` keeps this safe on darwin where the my.tools
  # option isn't defined.
  fullTools = !isLinux || (osConfig.my.tools.full or true);
in
{
  imports = [ inputs.nix-index-database.homeModules.nix-index ];

  # Gates version-dependent defaults (neovim providers off, hermetic
  # activation PATH, copied darwin apps). No on-disk user state depends on
  # the old defaults, so this tracks the home-manager release.
  home.stateVersion = "26.05";

  xdg.enable = true;

  # Skip building the HM manuals and the HM/nixpkgs version-mismatch check;
  # measurably faster eval on every rebuild.
  manual.manpages.enable = false;
  manual.html.enable = false;
  manual.json.enable = false;
  home.enableNixpkgsReleaseCheck = false;

  # nix-locate <file> and comma (`, <cmd>` runs an uninstalled program),
  # backed by the prebuilt nix-index database (no manual `nix-index` run).
  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;

  # Skip the command-not-found handler: it runs a slow nix-locate database
  # scan on every unknown command (~1s per typo). comma still works.
  programs.nix-index.enableBashIntegration = false;
  programs.nix-index.enableZshIntegration = false;

  #---------------------------------------------------------------------
  # Packages
  #---------------------------------------------------------------------

  # Packages I always want installed. Most packages I install using
  # per-project flakes sourced with direnv and nix-shell, so this is
  # not a huge list.
  #
  # This is the default home for any cross-platform CLI tool: it applies
  # to every host on both Linux and macOS. Reserve the modules/ aggregates
  # for Linux system-level packages and users/mich/darwin.nix homebrew for
  # macOS GUI apps. Don't list a package in more than one layer.
  #
  # The base list is the lean set every host gets, appliance images
  # included; the second list is the interactive toolkit and stays off
  # appliance images to keep their closures small.
  home.packages = [
    pkgs.dnsutils
    pkgs.dust
    pkgs.fd
    pkgs.fzf
    pkgs.git
    pkgs.htop
    pkgs.jq
    pkgs.ripgrep
    pkgs.tree
    pkgs.watch
    pkgs.wget
    pkgs.xz
    pkgs.zstd
  ]
  ++ (lib.optionals fullTools [
    pkgs.act
    pkgs.asciinema
    pkgs.ast-grep
    pkgs.bitwarden-cli
    pkgs.claude-code
    pkgs.codex
    pkgs.coreutils-prefixed
    pkgs.cosign
    pkgs.croc
    pkgs.duckdb
    pkgs.ffmpeg
    pkgs.git-ls # ls that shows each file's git status and last commit
    pkgs.gitleaks
    pkgs.hashcat
    pkgs.jadx
    pkgs.kubo
    pkgs.miller
    pkgs.nix-du # store disk-usage graph (pipe to graphviz `dot`)
    pkgs.nix-tree # interactive closure/dependency explorer
    pkgs.nmap
    pkgs.nnn
    pkgs.oils-for-unix
    pkgs.p7zip
    pkgs.pre-commit
    pkgs.python314
    pkgs.qpdf
    pkgs.restic
    pkgs.rtorrent
    pkgs.tor
    pkgs.torsocks
    pkgs.unicorn
    pkgs.visidata
    pkgs.yubikey-manager

    # Node is required for Copilot.vim
    pkgs.nodejs_26
  ])
  ++ (lib.optionals isDarwin [
    # programs.gpg is Linux-only here, so provide the gnupg binary on darwin.
    pkgs.gnupg
    # Replaces the brew poppler (pdftotext, pdfinfo, …).
    pkgs.poppler-utils
    # unrar is unfree; keep it off the free-only Linux hosts.
    pkgs.unrar
    # Set Launch Services file associations (also used by home.activation
    # below); in PATH for ad-hoc `duti -x md` style queries.
    pkgs.duti
    # CLI to switch audio I/O devices; macOS-only.
    pkgs.switchaudio-osx
    # Sudoless performance monitoring CLI for Apple Silicon (CPU/GPU/power).
    pkgs.macmon
    # DDC control of external monitors (brightness, contrast, input);
    # Apple Silicon only. ~/.bin/bright drives it.
    pkgs.m1ddc
    # Runs language models locally. Darwin-only because neon is the one host
    # with a GPU to run them on; the Linux VMs get no passthrough.
    pkgs.ollama
  ])
  ++ (lib.optionals gui [
    # Under VMware's vmwgfx GPU, Chromium's GPU-process sandbox blocks the lazy
    # load of Mesa's GBM driver (dri_gbm.so), so GPU acceleration falls back to
    # software. Dropping only the GPU-process sandbox (renderer sandbox stays)
    # lets it reach the driver and use the SVGA3D hardware path.
    (pkgs.chromium.override { commandLineArgs = "--disable-gpu-sandbox"; })
    pkgs.firefox
    pkgs.rofi
    pkgs.zathura
    pkgs.xfce4-terminal
  ])
  # GUI apps from nix on Linux graphical workstations and on macOS (preferred
  # over a manually-installed Zed.app so the version is declarative and current);
  # not on headless hosts (servers, apple-vm) which have nothing to draw to.
  ++ (lib.optionals (gui || isDarwin) [
    pkgs.sioyek
    pkgs.zed-editor
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  # Both shells are fully dotfile-managed (no programs.bash/zsh): env vars,
  # aliases, history and hooks live in the files below. bash_profile and
  # zshenv source hm-session-vars.sh themselves for the HM-generated env
  # (GNUPGHOME, XDG dirs, locale archive) — before their own exports, so
  # the dotfiles win.
  home.file.".inputrc".source = ./inputrc;
  home.file.".vimrc".source = ./vimrc;
  home.file.".tmux.conf".source = ./tmux.conf;
  home.file.".bash_env".source = ./bash_env;
  home.file.".bash_profile".source = ./bash_profile;
  home.file.".bashrc".source = ./bashrc;
  home.file.".bash_logout".source = ./bash_logout;

  home.file.".zshenv".source = ./zshenv;
  home.file.".zprofile".source = ./zprofile;
  home.file.".zshrc".source = ./zshrc;
  home.file.".zlogout".source = ./zlogout;
  home.file.".zsh_done".source = ./zsh_done;

  # Global agent instructions, version-controlled and synced across hosts.
  home.file.".claude/CLAUDE.md".source = ./claude/CLAUDE.md;

  # Skills stay a real directory (recursive) so ad-hoc skills can be
  # drafted in place before being promoted into the repo.
  home.file.".claude/skills" = {
    source = ./claude/skills;
    recursive = true;
  };

  # Personal scripts; both shells put ~/.bin on PATH. A real directory
  # (recursive) so ad-hoc scripts can live alongside the managed ones.
  home.file.".bin" = {
    source = ./bin;
    recursive = true;
  };

  # Keep Zed from phoning home: no AI features, no telemetry.
  home.file.".config/zed/settings.json".text = builtins.toJSON {
    disable_ai = true;
    telemetry = {
      diagnostics = false;
      metrics = false;
    };
    vim_mode = true;
    load_direnv = "direct";
  };

  # macOS file associations: register Zed as the default app for these
  # types with Launch Services. duti resolves the bundle ID (dev.zed.Zed),
  # so this is independent of the app's store path. Roles: viewer, editor,
  # or all (all also claims Finder double-click). Add lines to claim more
  # types; removing a line does not un-claim it — reassign it instead.
  home.activation.fileAssociations = lib.mkIf isDarwin (
    let
      dutiSettings = pkgs.writeText "duti-settings" ''
        # bundle-id    UTI or .extension            role
        dev.zed.Zed    net.daringfireball.markdown  all
        dev.zed.Zed    .md                          all
        dev.zed.Zed    .markdown                    all
      '';
      # lsregister forces Launch Services to index the copied app bundles;
      # without it duti fails on a first activation where the app has never
      # been seen (bundle ID not yet known).
      lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister";
    in
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${lsregister} -f -R "$HOME/Applications/Home Manager Apps" || true
      run ${pkgs.duti}/bin/duti ${dutiSettings} \
        || echo "warning: duti could not apply all file associations"
    ''
  );

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  # neovim on every host (the dotfiles set VISUAL/EDITOR to nvim).
  programs.neovim.enable = true;

  programs.gpg.enable = !isDarwin;

  programs.ssh = {
    enable = true;
    # Use OpenSSH's built-in defaults rather than HM's (which match anyway
    # but trigger a deprecation warning).
    enableDefaultConfig = false;
    # Keeps your hand-maintained hosts in a separate file that HM doesn't
    # rewrite. After the first activation, move ~/.ssh/config.before-hm
    # to ~/.ssh/config.local and your existing hosts will be picked up.
    includes = [ "~/.ssh/config.local" ];
    settings =
      let
        # Hosts running this repo's config (plus anything on the tailnet).
        fleet = [
          "dev"
          "nitrogen"
          "helium"
          "*.ts.net"
        ];
      in
      {
        # Applies to every host: multiplex connections over one master socket
        # (faster subsequent sessions, kept alive in the background).
        "*" = {
          ControlMaster = "auto";
          ControlPath = "~/.ssh/%r@%h:%p";
          ControlPersist = "yes";
        }
        # Sign with Secure Enclave-backed (sk-type) keys via the system
        # provider. Only consulted for sk keys; other key types unaffected.
        // lib.optionalAttrs isDarwin {
          SecurityKeyProvider = "/usr/lib/ssh-keychain.dylib";
        };
        dev = {
          HostName = "192.168.85.146";
          User = "mich";
          IdentityFile = "~/.ssh/id_ed25519";
        };
        # Fleet hosts get agent forwarding so sudo there can authenticate
        # against the local agent (pam_rssh). Scoped to owned machines and
        # the tailnet, never "*": a forwarded socket is usable by the remote
        # host's root for as long as the session lasts.
        ${lib.concatStringsSep " " fleet} = {
          ForwardAgent = "yes";
        };
        # Machines outside the fleet lack ghostty's terminfo, so force a
        # terminal type they are guaranteed to know; the fleet installs
        # ghostty.terminfo and sees the real TERM.
        ${"* " + lib.concatMapStringsSep " " (h: "!" + h) fleet} = {
          SetEnv = {
            TERM = "xterm-256color";
          };
        };
      };
  };

  programs.direnv = {
    enable = true;
    # Adds `use flake` / `use nix` understanding so per-project flakes
    # auto-load when you cd into them.
    nix-direnv.enable = true;

    # direnv sources direnv/lib/*.sh (where nix-direnv lives) before this
    # direnvrc, so nix_direnv_manual_reload is defined by the time it runs.
    stdlib = ''
      # No default route: serve nix-direnv's cached environment instead of
      # evaluating the flake, which would block on a fetch.
      if ! ${if isDarwin then "route -n get default" else "ip route get 1.1.1.1"} >/dev/null 2>&1; then
        nix_direnv_manual_reload
      fi
    '';

    config = {
      whitelist = {
        prefix = [
          "$HOME/code/go/src/github.com/moosterhof"
          "$HOME/code/go/src/github.com/micheloosterhof"
        ];

        exact = [ "$HOME/.envrc" ];
      };
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      hunk-header-style = "omit";
      side-by-side = true;
    };
  };

  programs.git = {
    enable = true;
    signing = {
      key = "523D5DC389D273BC";
      signByDefault = false;
    };
    settings = {
      user.name = "Michel Oosterhof";
      user.email = "michel@oosterhof.net";
      alias = {
        cleanup = "!git branch --merged | grep  -v '\\*\\|master\\|develop' | xargs -n 1 -r git branch -d";
        prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
        root = "rev-parse --show-toplevel";
        wip = "for-each-ref --sort='authordate:iso8601' --format=' %(color:green)%(authordate:relative)%09%(color:white)%(refname:short)' refs/heads";
        st = "status --short -uno";
        ci = "commit";
        ca = "commit --amend";
        caa = "commit -a --amend";
        br = "branch";
        co = "checkout";
        df = "diff";
        lg = "log -p --pretty=fuller --abbrev-commit";
        lgg = "log --pretty=fuller --abbrev-commit --stat";
        up = "pull --rebase";
      };
      branch.autosetuprebase = "always";
      color.ui = true;
      core.askPass = ""; # needs to be empty to use terminal for ask pass
      # macOS: tokens live in the Keychain. Linux: GitHub goes over SSH
      # (url rewrite), so no helper is needed and no token touches disk.
      credential.helper = lib.mkIf isDarwin "osxkeychain";
      github.user = "micheloosterhof";
      push.default = "tracking";
      # First push of a new branch creates the upstream, no --set-upstream.
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
      # Drop remote-tracking refs for branches deleted upstream on fetch.
      fetch.prune = true;
      # Remember conflict resolutions and replay them (pays off with the
      # rebase-heavy workflow: autosetuprebase + pull.rebase).
      rerere.enabled = true;
      rerere.autoUpdate = true;
      # Show the common ancestor in conflict markers.
      merge.conflictstyle = "zdiff3";
      # GitHub over SSH with the provisioned ed25519 key, so clones and
      # pushes authenticate without HTTPS tokens.
      url."git@github.com:".insteadOf = lib.mkIf isLinux "https://github.com/";
    };

    # Global excludes applied to every repo, in addition to per-repo
    # .gitignore. Includes safety nets for secrets that must never be
    # committed (ssh keys, gnupg material).
    ignores = [
      ".ICEauthority"
      ".DS_Store"
      ".Xauthority"
      ".Trash"
      ".dbus"
      ".dircolors.db"
      ".esd_auth"
      ".gnupg/gpg-agent-info-*"
      ".gnupg/pubring.gpg"
      ".gnupg/pubring.gpg~"
      ".gnupg/random_seed"
      ".gnupg/revoke.asc"
      ".gnupg/secring.gpg"
      ".gnupg/trustdb.gpg"
      ".irssi/away.log"
      ".irssi/private_key.prv"
      ".irssi/public_key.pub"
      ".irssi/serverkeys/*"
      ".pulse"
      ".recently-used.xbel"
      ".ssh/authorized_keys"
      ".ssh/known_hosts"
      ".steam*"
      ".xsession-errors"
      ".claude"
      ".direnv"
      "**/.claude/settings.local.json"
    ];
  };

  programs.jujutsu = {
    enable = true;
    settings = {
      user = {
        name = "Michel Oosterhof";
        email = "michel@oosterhof.net";
      };
      ui = {
        default-command = "log";
      };
    };
  };

  programs.gh = {
    enable = true;
    # Keep gh out of git's credential chain; auth stays on osxkeychain
    # (macOS) / SSH (Linux) as configured under programs.git.
    gitCredentialHelper.enable = false;
    settings = {
      git_protocol = "https";
      aliases = {
        co = "pr checkout";
      };
    };
  };

  programs.go = {
    enable = true;
    env.GOPATH = "${config.home.homeDirectory}/code/go";
    env.GOPRIVATE = [
      "github.com/micheloosterhof"
      "github.com/cowrie"
      "rfc822.mx"
    ];
  };

  programs.ghostty = {
    enable = gui || isDarwin;

    # On macOS Ghostty is installed from the Homebrew cask, not nixpkgs (which
    # has no darwin build). Setting the package to null makes home-manager
    # write the config without trying to install the binary.
    package = lib.mkIf isDarwin null;

    settings = {
      # JetBrains Mono for text; the symbols-only Nerd Font supplies glyphs it
      # lacks (powerline, devicons) without needing a patched font.
      font-family = [
        "JetBrains Mono"
        "Symbols Nerd Font Mono"
      ];

      # JetBrains Mono covers neither runes nor circled digits, and the system
      # fallbacks for them (Apple Symbols, Arial Unicode MS) are proportional —
      # their glyphs run up to 165% of the cell and collide with the next one.
      # JuliaMono draws both ranges at exactly the 0.6em cell width.
      font-codepoint-map = [
        "U+16A0-U+16F8=JuliaMono"
        "U+2460-U+2473,U+2780-U+2789=JuliaMono"
      ];

      # Route launches through the running instance via D-Bus for instant
      # new windows; pairs with the systemd user service and "ghostty
      # +new-window" i3 keybind.
      gtk-single-instance = true;

      keybind = [
        "super+c=copy_to_clipboard"
        "super+v=paste_from_clipboard"
        "super+equal=increase_font_size:1"
        "super+plus=increase_font_size:1"
        "super+minus=decrease_font_size:1"
        "super+zero=reset_font_size"
      ];
    };
  };

  programs.tmux = {
    enable = true;
    terminal = "xterm-256color";
    shortcut = "l";
    secureSocket = false;

    extraConfig = ''
      set -ga terminal-overrides ",*256col*:Tc"

      bind -n C-k send-keys "clear"\; send-keys "Enter"
    '';
  };

  programs.i3status = {
    enable = gui;

    general = {
      colors = true;
      color_good = "#8C9440";
      color_bad = "#A54242";
      color_degraded = "#DE935F";
    };

    modules = {
      ipv6.enable = false;
      "wireless _first_".enable = false;
      "battery all".enable = false;
    };
  };

  services.gpg-agent = {
    enable = isLinux;
    pinentry.package = pkgs.pinentry-tty;

    # cache the keys forever so we don't get asked for a password
    defaultCacheTtl = 31536000;
    maxCacheTtl = 31536000;
  };

  xresources.extraConfig = builtins.readFile ./Xresources;

  # Make cursor not tiny on HiDPI screens
  home.pointerCursor = lib.mkIf gui {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
    x11.enable = true;
  };

  xsession.windowManager.i3 = lib.mkIf gui {
    enable = true;
    config = {
      modifier = "Mod4";
      terminal = "ghostty";
      menu = "${pkgs.rofi}/bin/rofi -show drun -show-icons";
      fonts = {
        names = [
          "JetBrains Mono"
          "monospace"
        ];
        size = 10.0;
      };
      bars = [
        {
          position = "bottom";
          statusCommand = "${pkgs.i3status}/bin/i3status";
          fonts = {
            names = [
              "JetBrains Mono"
              "monospace"
            ];
            size = 10.0;
          };
        }
      ];
      keybindings = lib.mkOptionDefault {
        "Mod4+Return" = "exec ghostty +new-window";
        "Mod4+d" = "exec rofi -show drun -show-icons";
        # Manually refresh resolution to Fusion's preferred mode.
        "Mod4+F5" = "exec xrandr-auto";
      };
      startup = [
        # Pick Fusion's preferred SVGA resolution on session start.
        # vmware-user-suid-wrapper would normally drive auto-resize on
        # Fusion window changes, but it crashes on aarch64 open-vm-tools
        # with a GTK init error — so we hit it once at startup and bind
        # Mod4+F5 above to refresh on demand.
        {
          command = "xrandr-auto";
          always = false;
          notification = false;
        }
      ];
    };
  };
}
