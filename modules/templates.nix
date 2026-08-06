# ABOUTME: Flake templates that scaffold per-project dev shells. Use with
# ABOUTME: `nix flake init -t github:micheloosterhof/nix#<name>`.
{ ... }:
{
  flake.templates = {
    security = {
      path = ../templates/security;
      description = "Security / reverse-engineering tools dev shell";
    };
    biotools = {
      path = ../templates/biotools;
      description = "Bioinformatics tools dev shell";
    };
    cowrie = {
      path = ../templates/cowrie;
      description = "Cowrie honeypot dev shell";
    };
    rust = {
      path = ../templates/rust;
      description = "Rust dev shell";
    };
    go = {
      path = ../templates/go;
      description = "Go dev shell";
    };
    python = {
      path = ../templates/python;
      description = "Python dev shell";
    };
    typescript = {
      path = ../templates/typescript;
      description = "TypeScript dev shell";
    };
  };
}
