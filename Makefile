# Connectivity info for a remote host (VM, bare metal, or cloud)
NIXADDR ?= unset
NIXPORT ?= 22
NIXUSER ?= mich

# Get the path to this Makefile and directory
MAKEFILE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# We need to do some OS switching below.
UNAME := $(shell uname)

# NIXNAME identifies the remote host's nixosConfiguration (used by vm/* targets,
# which despite the prefix work for any ssh-reachable host: the VMs, helium, oxygen).
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
	nix flake check

.PHONY: hooks
hooks: ## Install the git pre-commit hooks
	pre-commit install

rebuild: ## Build + activate the current host (Darwin or NixOS)
ifeq ($(UNAME), Darwin)
	sudo darwin-rebuild switch --flake "$$(pwd)#${LOCAL_NAME}"
else
	sudo nixos-rebuild switch --flake ".#${LOCAL_NAME}"
endif

test: ## Build + activate without persisting (no boot entry)
ifeq ($(UNAME), Darwin)
	sudo darwin-rebuild test --flake "$$(pwd)#${LOCAL_NAME}"
else
	sudo nixos-rebuild test --flake ".#${LOCAL_NAME}"
endif

build: ## Build the configuration only (no activation)
ifeq ($(UNAME), Darwin)
	darwin-rebuild build --flake "$$(pwd)#${LOCAL_NAME}"
else
	nixos-rebuild build --flake ".#${LOCAL_NAME}"
endif

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
	sudo nixos-rebuild switch --rollback --flake ".#${LOCAL_NAME}"
endif

.PHONY: repl
repl: ## Open a nix repl with this flake's outputs in scope
	nix repl .

.PHONY: gc
gc: ## Delete system generations older than 7d and collect store garbage
	sudo nix profile wipe-history --profile $(SYSTEM_PROFILE) --older-than 7d
	nix store gc

# The customized linux-builder image is an aarch64-linux derivation that
# cache.nixos.org does not carry; neon's CI build substitutes it from the
# personal cachix cache. Re-run this after a flake.lock bump changes the
# image (the failing neon CI job is the reminder).
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

# Backup secrets so that we can transer them to new machines via
# sneakernet or other means.
.PHONY: secrets/backup
secrets/backup: ## Tar ~/.ssh and ~/.gnupg into backup.tar.gz
	tar -czvf $(MAKEFILE_DIR)/backup.tar.gz \
		-C $(HOME) \
		--exclude='.gnupg/.#*' \
		--exclude='.gnupg/S.*' \
		--exclude='.gnupg/*.conf' \
		--exclude='.ssh/environment' \
		.ssh/ \
		.gnupg

.PHONY: secrets/restore
secrets/restore: ## Untar backup.tar.gz back into ~
	if [ ! -f $(MAKEFILE_DIR)/backup.tar.gz ]; then \
		echo "Error: backup.tar.gz not found in $(MAKEFILE_DIR)"; \
		exit 1; \
	fi
	echo "Restoring SSH keys and GPG keyring from backup..."
	mkdir -p $(HOME)/.ssh $(HOME)/.gnupg
	tar -xzvf $(MAKEFILE_DIR)/backup.tar.gz -C $(HOME)
	chmod 700 $(HOME)/.ssh $(HOME)/.gnupg
	chmod 600 $(HOME)/.ssh/* || true
	chmod 700 $(HOME)/.gnupg/* || true

# Provision a fresh NixOS install onto any ssh-reachable Linux (an ISO-booted
# VM, or a running distro that nixos-anywhere kexecs into the installer).
# Partitions per the disko spec in the host file, installs the flake config and
# reboots. Set NIXADDR + NIXNAME (+ NIXPORT). Afterwards run vm/secrets.
# NOTE: nixos-anywhere kexec needs enough RAM; a tiny host (oxygen, ~1 GB) needs
# nixos-infect instead.
vm/provision: ## Install NixOS onto a remote host via nixos-anywhere + disko
	nix run github:nix-community/nixos-anywhere -- \
		--flake ".#$(NIXNAME)" \
		--ssh-port $(NIXPORT) \
		root@$(NIXADDR)

# copy our secrets into the remote host
vm/secrets: ## rsync ~/.gnupg and ~/.ssh to the remote host
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
vm/copy: ## rsync this repo into the remote host at /nix-config
	rsync -av --delete -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='vendor/' \
		--exclude='.git/' \
		--exclude='.git-crypt/' \
		--exclude='.jj/' \
		--exclude='iso/' \
		--rsync-path="sudo rsync" \
		$(MAKEFILE_DIR)/ $(NIXUSER)@$(NIXADDR):/nix-config

# run the nixos-rebuild switch command. This does NOT copy files so you
# have to run vm/copy before.
vm/rebuild: ## Run nixos-rebuild switch on the remote host (vm/copy first)
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
                sudo NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake \"/nix-config#${NIXNAME}\" \
	"

# Bump flake.lock to current branch tips and roll the remote host forward.
# Note: nix flake update rewrites the whole lockfile, so the next local
# `make rebuild` will pick up the same bumps.
.PHONY: vm/update
vm/update: ## Bump flake.lock and rebuild the remote host
	nix flake update
	$(MAKE) vm/copy
	$(MAKE) vm/rebuild

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

# Build a WSL installer
.PHONY: wsl
wsl: ## Build a WSL installer tarball
	 nix build ".#nixosConfigurations.wsl.config.system.build.installer"

# Build a Google Compute Engine image (a GCS-uploadable tarball). aarch64
# builds on the Mac's linux-builder; x86_64 needs a native x86_64 builder,
# so build that arch in CI (or with an x86_64 remote builder).
GCE_ARCH ?= x86_64-linux
.PHONY: gce/image
gce/image: ## Build a GCE image; prints /nix/store path (GCE_ARCH=x86_64-linux|aarch64-linux)
	@nix build --no-link --print-out-paths ".#packages.$(GCE_ARCH).gce-image"

# Upload the built image to a GCS bucket and register it as a Compute image.
# Set GCE_BUCKET and GCE_PROJECT. gcloud/gsutil run via nix (no local install).
# GCE resource names forbid underscores, so the arch is dash-mangled.
GCE_IMAGE_NAME ?= nixos-$(subst _,-,$(GCE_ARCH))
# Confidential VM feature tags (x86_64 only: SEV on N2D/C2D, SEV-SNP on
# N2D/C3D, TDX on C3) so instances can launch with hardware memory
# encryption. The stock nixpkgs kernel carries the guest support
# (AMD_MEM_ENCRYPT, SEV_GUEST, INTEL_TDX_GUEST; live migration and TDX need
# kernel >= 6.6). SNP/TDX machine series additionally require registering
# the GVNIC feature before instances will launch.
GCE_GUEST_OS_FEATURES = UEFI_COMPATIBLE
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
			--guest-os-features=$(GCE_GUEST_OS_FEATURES) \
			--source-uri "gs://$(GCE_BUCKET)/$$(basename "$$TARBALL")"
