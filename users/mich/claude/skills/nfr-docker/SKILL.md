---
name: nfr-docker
description: Container and deployment standards - Dockerfile hardening, distroless images, capability dropping, SBOM, multi-arch builds, Debian packaging. Load before writing or reviewing Dockerfiles, compose files, or deployment config.
---

# Container & Deployment Standards

## Dockerfile

- Multi-stage builds: separate builder and runtime stages
- Minimal runtime images: prefer `distroless`, then `*-slim` variants
- No shell in production images where possible (distroless)
- Non-root user: create a dedicated service user in the builder stage
- Dependency caching: separate layer for dependency installation before
  copying source (Cargo, pip, go mod)
- `.dockerignore`: keep build context small
- Lint with hadolint (`.hadolint.yaml`)

## Runtime Hardening

- Read-only root filesystem: `--read-only` with `--tmpfs /tmp` where needed
- Capability dropping: `--cap-drop=ALL`, add back only what's needed
  (e.g., `cap_net_bind_service` for privileged ports via `setcap`)
- Volume mounts for config (`/opt/<service>/conf`) and data
  (`/opt/<service>/var`). Never bake runtime data into the image.

## Build & Metadata

- OCI labels: `org.opencontainers.image.*` metadata
- SBOM + provenance: enable in buildx (`--sbom=true --provenance=true`)
- Multi-architecture: amd64 + arm64 at minimum

## Debian

- `.deb` packages for production deployment where applicable
