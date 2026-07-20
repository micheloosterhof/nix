# ABOUTME: Local validation: `nix flake check` (or `make lint`). Keeps the
# ABOUTME: checks lightweight so they run without the Linux builder.
{ inputs, ... }:
{
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  perSystem =
    { system, ... }:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};

      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";

        programs.nixfmt.enable = true;

        # Flag dead code (unused let bindings, etc). Lambda pattern names
        # are ignored because { config, lib, pkgs, ... } module arguments
        # are idiomatic even when unused.
        programs.deadnix.enable = true;
        programs.deadnix.no-lambda-pattern-names = true;

        # Shell scripts (*.sh only, so the zsh/bash dotfiles under users/
        # are untouched) and GitHub workflow files. The templates' .envrc
        # files are direnv syntax, not shell — shellcheck can't parse them.
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.excludes = [
          "**/.envrc"
        ];
        programs.shfmt.enable = true;
        programs.actionlint.enable = true;
      };
    in
    {
      formatter = treefmtEval.config.build.wrapper;

      checks = {
        # Every file must be clean under `nix fmt` (treefmt: nixfmt, deadnix,
        # shellcheck, shfmt, actionlint).
        formatting = treefmtEval.config.build.check inputs.self;

        # Pure-eval regression tests for the host composition wiring (tests/).
        # Failures throw during evaluation, so even `nix flake check
        # --no-build` reports them; the derivation is just a marker.
        eval-tests =
          let
            failures = import ../tests {
              inherit (inputs) self;
              inherit inputs;
              inherit (inputs.nixpkgs) lib;
            };
          in
          if failures == [ ] then
            pkgs.runCommand "eval-tests" { } "touch $out"
          else
            throw "eval-tests failed: ${builtins.toJSON failures}";
      };
    };
}
