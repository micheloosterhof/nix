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

    # Secrets: sops-encrypted files in secrets/, decrypted at activation with
    # each host's SSH host key as its age identity (see modules/secrets.nix).
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # One formatter/linter front-end: `nix fmt` and the formatting check
    # (nixfmt, deadnix, shellcheck, shfmt, actionlint) share one config.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Trials on dev (modules/experimental/). Rex is an unfree prebuilt
    # binary; the lock records the immutable per-release URL behind the
    # channel URL. Its own nixpkgs only patchelfs the binary, so stable will do.
    rex = {
      url = "https://pkgs.superlogical.com/rex/nix/preview.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # No follows: hermes-agent's Python environment is built and tested
    # against its own locked nixpkgs and uv2nix set.
    hermes-agent.url = "github:NousResearch/hermes-agent";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
