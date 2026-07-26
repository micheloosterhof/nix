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
  # to every host on both Linux and macOS. Reserve machines/vm-shared.nix
  # for Linux system-level packages and users/mich/darwin.nix homebrew for
  # macOS GUI apps. Don't list a package in more than one layer.
  home.packages = [
    pkgs.act
    pkgs.asciinema
    pkgs.ast-grep
    pkgs.bitwarden-cli
    pkgs.cargo
    pkgs.claude-code
    pkgs.clippy
    pkgs.coreutils-prefixed
    pkgs.cosign
    pkgs.croc
    pkgs.dnsutils
    pkgs.duckdb
    pkgs.dust
    pkgs.fd
    pkgs.ffmpeg
    pkgs.fzf
    pkgs.git
    pkgs.gitleaks
    pkgs.golangci-lint
    pkgs.hashcat
    pkgs.htop
    pkgs.jadx
    pkgs.jq
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
    pkgs.ripgrep
    pkgs.rtorrent
    pkgs.rustc
    pkgs.rustfmt
    pkgs.sioyek
    pkgs.tor
    pkgs.torsocks
    pkgs.tree
    pkgs.unicorn
    pkgs.visidata
    pkgs.watch
    pkgs.wget
    pkgs.xz
    pkgs.yubikey-manager
    pkgs.zstd

    pkgs.gopls

    # Node is required for Copilot.vim
    pkgs.nodejs_24
  ]
  ++ (lib.optionals isDarwin [
    # programs.gpg is Linux-only here, so provide the gnupg binary on darwin.
    pkgs.gnupg
    # Replaces the brew poppler (pdftotext, pdfinfo, …).
    pkgs.poppler-utils
    # unrar is unfree; keep it off the free-only Linux hosts.
    pkgs.unrar
    # CLI to switch audio I/O devices; macOS-only.
    pkgs.switchaudio-osx
    # Sudoless performance monitoring CLI for Apple Silicon (CPU/GPU/power).
    pkgs.macmon
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
  # GUI editor from nix on Linux graphical workstations and on macOS (preferred
  # over a manually-installed Zed.app so the version is declarative and current);
  # not on headless hosts (WSL, apple-vm) which have nothing to draw to.
  ++ (lib.optionals (gui || isDarwin) [
    pkgs.zed-editor
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "nvim";
    PAGER = "less -FirSwX";
    MANPAGER = "less";
  };

  home.file.".inputrc".source = ./inputrc;
  home.file.".vimrc".source = ./vimrc;
  home.file.".tmux.conf".source = ./tmux.conf;
  home.file.".bash_env".source = ./bash_env;

  home.file.".zshenv".source = ./zshenv;
  home.file.".zprofile".source = ./zprofile;
  home.file.".zshrc".source = ./zshrc;
  home.file.".zlogout".source = ./zlogout;
  home.file.".zsh_kubectl".source = ./zsh_kubectl;

  # Global agent instructions, version-controlled and synced across hosts.
  home.file.".claude/CLAUDE.md".source = ./claude/CLAUDE.md;

  # Skills stay a real directory (recursive) so ad-hoc skills can be
  # drafted in place before being promoted into the repo.
  home.file.".claude/skills" = {
    source = ./claude/skills;
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

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  # neovim on every host (EDITOR is already nvim above).
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
    settings = {
      # Applies to every host: multiplex connections over one master socket
      # (faster subsequent sessions, kept alive in the background), and force a
      # terminal type the remote is guaranteed to know.
      "*" = {
        ControlMaster = "auto";
        ControlPath = "~/.ssh/%r@%h:%p";
        ControlPersist = "yes";
        SetEnv = {
          TERM = "xterm-256color";
        };
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
    };
  };

  programs.bash = {
    enable = true;
    shellOptions = [ ];
    historyControl = [
      "ignoredups"
      "ignorespace"
    ];
    initExtra = builtins.readFile ./bashrc;
    profileExtra = builtins.readFile ./bash_profile;
    logoutExtra = builtins.readFile ./bash_logout;

    shellAliases = {
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gcp = "git cherry-pick";
      gdiff = "git diff";
      gl = "git prettylog";
      gp = "git push";
      gs = "git status";
      gt = "git tag";
      timeout = "gtimeout";
    };
  };

  programs.direnv = {
    enable = true;
    # Adds `use flake` / `use nix` understanding so per-project flakes
    # auto-load when you cd into them.
    nix-direnv.enable = true;

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
