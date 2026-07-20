# Project dev-shell templates

Scaffold a new project directory with a ready-to-use Nix dev shell. Each
template drops a `flake.nix` (the dev shell) and a `.envrc` (`use flake`) into
the current directory; with direnv these load automatically.

## Usage

```sh
mkdir ~/work/myproject && cd ~/work/myproject
nix flake init -t github:micheloosterhof/nix#security
direnv allow          # if using direnv; otherwise: nix develop
```

From a local checkout of this repo you can also use `.#security`, etc.

## Available templates

| Template   | Tools |
|------------|-------|
| `security` | ghidra, jadx, hashcat, unicorn |
| `biotools` | bwa, minimap2, samtools, bcftools, htslib, fastp, fastqc |
| `cowrie`   | inetutils (telnet/ftp/tftp clients for testing listeners) |

Each template pins its own `nixpkgs`, so the project owns and can evolve its
environment independently of this config.
