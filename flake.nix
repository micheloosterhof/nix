{
  description = "Michel's NixOS and nix-darwin configurations";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Top-level module system (the dendritic pattern): every file under
    # modules/ is a flake-parts module, auto-imported by import-tree.
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "github:vic/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Prebuilt nix-index database -> nix-locate <file> + comma (`, <cmd>`).
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Wayland clipboard backend for open-vm-tools, for host<->guest copy/paste
    # under the Fusion guest's sway specialisation (machines/sway.nix).
    clipway = {
      url = "github:krisztianfekete/clipway";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk layouts: the bare-metal / cloud server installs and
    # nixos-anywhere provisioning (make vm/provision).
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # One formatter/linter front-end: `nix fmt` and the formatting check
    # (nixfmt, deadnix, shellcheck, shfmt, actionlint) share one config.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
