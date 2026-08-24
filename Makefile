# Connectivity info for a remote host (VM, bare metal, or cloud)
NIXADDR ?= unset
NIXPORT ?= 22
NIXUSER ?= mich

# Get the path to this Makefile and directory
MAKEFILE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# We need to do some OS switching below.
UNAME := $(shell uname)

# NIXNAME identifies the remote host's nixosConfiguration, used by the
# remote/* targets (any ssh-reachable host: the VMs, helium, nitrogen).
NIXNAME ?= vm-aarch64-fusion

# LOCAL_NAME identifies the config for the LOCAL host's rebuild/test targets.
# On Darwin we always rebuild neon regardless of what NIXNAME is set to for
# the remote host workflow.
ifeq ($(UNAME), Darwin)
  LOCAL_NAME := neon
else
  LOCAL_NAME := $(NIXNAME)
endif

# SSH options that are used. These aren't meant to be overridden but are
# reused a lot so we just store them up here.
SSH_OPTIONS=-o PubkeyAuthentication=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_/-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: fmt
fmt: ## Format the repo with treefmt (nixfmt, deadnix, shellcheck, shfmt, actionlint)
	@nix fmt

.PHONY: fmt/check
fmt/check: ## Check formatting without writing changes
	@nix fmt -- --fail-on-change

.PHONY: lint
lint: ## Run flake checks (formatting + eval-tests)
	nix flake check --all-systems

.PHONY: hooks
hooks: ## Install the git pre-commit hooks
	pre-commit install

.PHONY: rebuild
rebuild: ## Build + activate the current host (Darwin or NixOS)
ifeq ($(UNAME), Darwin)
	sudo darwin-rebuild switch --flake "$$(pwd)#${LOCAL_NAME}"
else
	sudo nixos-rebuild switch --flake ".#${LOCAL_NAME}"
endif

.PHONY: test
test: ## Build + activate without persisting (no boot entry)
ifeq ($(UNAME), Darwin)
	sudo darwin-rebuild test --flake "$$(pwd)#${LOCAL_NAME}"
else
	sudo nixos-rebuild test --flake ".#${LOCAL_NAME}"
endif

.PHONY: build
build: ## Build the configuration only (no activation)
ifeq ($(UNAME), Darwin)
	darwin-rebuild build --flake "$$(pwd)#${LOCAL_NAME}"
else
	nixos-rebuild build --flake ".#${LOCAL_NAME}"
endif

.PHONY: check
check: ## Build + run activation checks without switching
ifeq ($(UNAME), Darwin)
	sudo darwin-rebuild check --flake "$$(pwd)#${LOCAL_NAME}"
else
	sudo nixos-rebuild dry-activate --flake ".#${LOCAL_NAME}"
endif

# Path to the active system profile (same on NixOS and nix-darwin).
SYSTEM_PROFILE := /nix/var/nix/profiles/system

.PHONY: upp
upp: ## Bump a single flake input: make upp INPUT=nixos-wsl
	@test -n "$(INPUT)" || { echo "Usage: make upp INPUT=<flake-input>"; exit 1; }
	nix flake update $(INPUT)

.PHONY: history
history: ## List system generations with dates
	nix profile history --profile $(SYSTEM_PROFILE)

.PHONY: rollback
rollback: ## Roll back to the previous system generation
ifeq ($(UNAME), Darwin)
	sudo darwin-rebuild --rollback
else
	sudo nixos-rebuild switch --rollback
endif

.PHONY: repl
repl: ## Open a nix repl with this flake's outputs in scope
	nix repl .

# 30d matches the declarative weekly GC policy (nix-settings.nix).
.PHONY: gc
gc: ## Delete system generations older than 30d and collect store garbage
	sudo nix profile wipe-history --profile $(SYSTEM_PROFILE) --older-than 30d
	nix store gc

# The customized linux-builder image is an aarch64-linux derivation that
# cache.nixos.org does not carry, and a fresh Mac cannot build it before it
# has a working builder. Seeding the cache from a Mac that already has one
# is what makes that first bootstrap possible.
.PHONY: cachix/seed
cachix/seed: ## Push the linux-builder image closure to the cachix cache
	nix build --no-link ".#darwinConfigurations.neon.config.nix.linux-builder.package"
	nix run nixpkgs#cachix -- push micheloosterhof \
		"$$(nix eval --raw '.#darwinConfigurations.neon.config.nix.linux-builder.package.outPath')"

.PHONY: store/verify
store/verify: ## Check the integrity of every store path
	nix store verify --all

.PHONY: store/repair
store/repair: ## Verify with content hashing and repair broken store paths
	sudo nix-store --verify --check-contents --repair

# Backup secrets so that we can transfer them to new machines via
# sneakernet or other means. The archive carries private ssh and gnupg keys,
# so it only ever exists encrypted under a passphrase (age -p): the plaintext
# stays in the pipe. pipefail so a tar failure isn't hidden by age's success,
# umask so the archive is unreadable to anyone else.
.PHONY: secrets/backup
secrets/backup: ## Tar ~/.ssh and ~/.gnupg into passphrase-encrypted backup.tar.gz.age
	set -o pipefail; umask 077; tar -czvf - \
		-C $(HOME) \
		--exclude='.gnupg/.#*' \
		--exclude='.gnupg/S.*' \
		--exclude='.gnupg/*.conf' \
		--exclude='.ssh/environment' \
		.ssh/ \
		.gnupg \
		| age --passphrase --output $(MAKEFILE_DIR)/backup.tar.gz.age

.PHONY: secrets/restore
secrets/restore: ## Decrypt backup.tar.gz.age back into ~
	if [ ! -f $(MAKEFILE_DIR)/backup.tar.gz.age ]; then \
		echo "Error: backup.tar.gz.age not found in $(MAKEFILE_DIR)"; \
		exit 1; \
	fi
	echo "Restoring SSH keys and GPG keyring from backup..."
	mkdir -p $(HOME)/.ssh $(HOME)/.gnupg
	set -o pipefail; umask 077; age --decrypt $(MAKEFILE_DIR)/backup.tar.gz.age \
		| tar -xzvf - -C $(HOME)
	chmod 700 $(HOME)/.ssh $(HOME)/.gnupg
	chmod 600 $(HOME)/.ssh/* || true
	chmod 700 $(HOME)/.gnupg/* || true

# Every remote/* target refuses to run against the NIXADDR placeholder;
# a stale or forgotten NIXADDR must fail here, not on the wrong machine.
.PHONY: remote/check-addr
remote/check-addr:
	@test "$(NIXADDR)" != "unset" || { \
		echo "error: NIXADDR is not set; pass NIXADDR=<host>"; exit 1; }

# Provision a fresh NixOS install onto any ssh-reachable Linux (an ISO-booted
# VM, or a running distro that nixos-anywhere kexecs into the installer).
# Partitions per the disko spec in the host file, installs the flake config and
# reboots. Set NIXADDR + NIXNAME (+ NIXPORT). Afterwards run remote/secrets.
# NOTE: nixos-anywhere kexec needs enough RAM; a tiny host (~1 GB) needs
# nixos-infect instead.
.PHONY: remote/provision
remote/provision: remote/check-addr ## Install NixOS onto a remote host via nixos-anywhere + disko
	@test "$(origin NIXNAME)" = "command line" || { \
		echo "error: remote/provision ERASES the target's disks;"; \
		echo "       pass NIXNAME=<host> explicitly (the default is not accepted here)"; exit 1; }
	@echo "Provisioning root@$(NIXADDR) as $(NIXNAME): disks will be repartitioned per its disko spec."
	nix run github:nix-community/nixos-anywhere -- \
		--flake ".#$(NIXNAME)" \
		--ssh-port $(NIXPORT) \
		root@$(NIXADDR)

# copy our secrets into the remote host
.PHONY: remote/secrets
remote/secrets: remote/check-addr ## rsync ~/.gnupg and ~/.ssh to the remote host
	# GPG keyring
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		--exclude='.#*' \
		--exclude='S.*' \
		--exclude='*.conf' \
		$(HOME)/.gnupg/ $(NIXUSER)@$(NIXADDR):~/.gnupg
	# SSH keys
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		--exclude='environment' \
		$(HOME)/.ssh/ $(NIXUSER)@$(NIXADDR):~/.ssh

# copy the Nix configurations into the remote host. --delete keeps /nix-config an
# exact mirror: stale files from earlier copies would otherwise be
# auto-imported by import-tree and break evaluation.
.PHONY: remote/copy
remote/copy: remote/check-addr ## rsync this repo into the remote host at /nix-config
	rsync -av --delete -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='.git/' \
		--exclude='.jj/' \
		--rsync-path="sudo rsync" \
		$(MAKEFILE_DIR)/ $(NIXUSER)@$(NIXADDR):/nix-config

# run the nixos-rebuild switch command. This does NOT copy files so you
# have to run remote/copy before.
.PHONY: remote/rebuild
remote/rebuild: remote/check-addr ## Run nixos-rebuild switch on the remote host (remote/copy first)
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
                sudo NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake \"/nix-config#${NIXNAME}\" \
	"

# Activate without a boot entry: if the new config kills the network, a
# provider-console reboot lands back on the old system. Run this before
# remote/rebuild on hosts where a bad switch means a trip to the console.
.PHONY: remote/test
remote/test: remote/check-addr ## Run nixos-rebuild test on the remote host (no boot entry; remote/copy first)
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
                sudo NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --flake \"/nix-config#${NIXNAME}\" \
	"

# Build the VMware VMDK and print its /nix/store path. No `result`
# symlink (--no-link), so old builds GC automatically without manual
# `rm result` first.
.PHONY: vm/image
vm/image: ## Build a VMware VMDK; prints /nix/store path
	@nix build --no-link --print-out-paths ".#nixosConfigurations.$(NIXNAME).config.system.build.vmwareImage"

# Create or refresh a VMware Fusion VM bundle from the built VMDK.
# Always overwrites the disk; only writes the .vmx template if missing
# so manual Fusion-side edits survive.
.PHONY: vm/launch
VM_NAME ?= dev
VM_BUNDLE_DIR ?= $(HOME)/Virtual Machines.localized
VM_BUNDLE = $(VM_BUNDLE_DIR)/$(VM_NAME).vmwarevm
vm/launch: ## Build VMDK and drop into a Fusion .vmwarevm bundle
	@mkdir -p "$(VM_BUNDLE)"
	@IMG=$$($(MAKE) --no-print-directory vm/image) && \
		cp -f "$$IMG"/*.vmdk "$(VM_BUNDLE)/$(VM_NAME).vmdk"
	@chmod u+w "$(VM_BUNDLE)/$(VM_NAME).vmdk"
	@[ -f "$(VM_BUNDLE)/$(VM_NAME).vmx" ] || \
		cp "$(MAKEFILE_DIR)/modules/hosts/$(VM_NAME).vmx" "$(VM_BUNDLE)/$(VM_NAME).vmx"
	@echo "VM bundle: $(VM_BUNDLE)"
	@echo "Start: open '$(VM_BUNDLE)'   or   vmrun start '$(VM_BUNDLE)/$(VM_NAME).vmx'"

# Build a Google Compute Engine image (a GCS-uploadable tarball). Assembled
# by systemd-repart — no KVM needed, any builder of the right arch works:
# aarch64 on the Mac's linux-builder, x86_64 in CI or on an x86_64 box.
GCE_ARCH ?= x86_64-linux
.PHONY: gce/image
gce/image: ## Build a GCE image; prints /nix/store path (GCE_ARCH=x86_64-linux|aarch64-linux)
	@nix build --no-link --print-out-paths ".#packages.$(GCE_ARCH).gce-image"

# Upload the built image to a GCS bucket and register it as a Compute image.
# Set GCE_BUCKET and GCE_PROJECT. gcloud/gsutil run via nix (no local install).
# GCE resource names forbid underscores, so the arch is dash-mangled.
# Standard GCP image lifecycle: each upload registers a uniquely
# timestamped image inside a stable per-arch family (one shared family
# would mix arches — --image-family resolves to the family's newest image
# regardless of architecture). Instances reference the family and always
# get the newest image; older ones stay behind for rollback.
GCE_IMAGE_FAMILY ?= nixos-$(subst _,-,$(GCE_ARCH))
GCE_IMAGE_NAME ?= $(GCE_IMAGE_FAMILY)-$(shell date -u +%Y%m%d-%H%M%S)
# GVNIC (both arches) lets instances attach the gVNIC NIC that newer
# machine series use or require (C3/C3D/H3/N4 on x86_64, C4A on aarch64)
# for higher network bandwidth; the image kernel carries the gve driver
# as a module, and virtio-net instances are unaffected.
# Confidential VM feature tags (x86_64 only: SEV on N2D/C2D, SEV-SNP on
# N2D/C3D, TDX on C3) so instances can launch with hardware memory
# encryption. The stock nixpkgs kernel carries the guest support
# (AMD_MEM_ENCRYPT, SEV_GUEST, INTEL_TDX_GUEST; live migration and TDX need
# kernel >= 6.6). The SNP (C3D) and TDX (C3) machine series additionally
# require GVNIC, registered above.
GCE_GUEST_OS_FEATURES = UEFI_COMPATIBLE,GVNIC
ifeq ($(GCE_ARCH),x86_64-linux)
GCE_GUEST_OS_FEATURES := $(GCE_GUEST_OS_FEATURES),SEV_CAPABLE,SEV_LIVE_MIGRATABLE_V2,SEV_SNP_CAPABLE,TDX_CAPABLE
endif
.PHONY: gce/upload
gce/upload: ## Upload + register the GCE image (set GCE_BUCKET, GCE_PROJECT)
	@test -n "$(GCE_BUCKET)" || { echo "set GCE_BUCKET=<gcs-bucket>"; exit 1; }
	@test -n "$(GCE_PROJECT)" || { echo "set GCE_PROJECT=<gcp-project>"; exit 1; }
	IMG=$$($(MAKE) --no-print-directory gce/image) && \
		TARBALL=$$(ls "$$IMG"/*.tar.gz) && \
		nix run nixpkgs#google-cloud-sdk -- storage cp "$$TARBALL" "gs://$(GCE_BUCKET)/" && \
		nix run nixpkgs#google-cloud-sdk -- compute images create "$(GCE_IMAGE_NAME)" \
			--project "$(GCE_PROJECT)" \
			--family "$(GCE_IMAGE_FAMILY)" \
			--labels=git-rev=$$(git -C "$(MAKEFILE_DIR)" describe --always --dirty),built=$$(date -u +%Y-%m-%d) \
			--guest-os-features=$(GCE_GUEST_OS_FEATURES) \
			--platform-key-file="$$IMG/cert.der" \
			--key-exchange-key-file="$$IMG/cert.der" \
			--signature-database-file="$$IMG/cert.der" \
			--source-uri "gs://$(GCE_BUCKET)/$$(basename "$$TARBALL")"
