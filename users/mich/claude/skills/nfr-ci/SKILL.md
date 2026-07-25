---
name: nfr-ci
description: CI/CD standards - GitHub Actions job set, cancel-in-progress, release automation, dependency updates, test matrices. Load before writing or reviewing CI workflows or release automation.
---

# CI/CD Standards

## GitHub Actions

- Primary CI/CD platform, but minimize GitHub-specific dependencies:
  tests must run locally via the same tools (tox, cargo test, go test,
  Playwright)
- Cancel in-progress workflows on new pushes

## Standard Jobs

| Job | Purpose |
|-----|---------|
| `check` | Format + lint |
| `test` | Unit tests (multiple language versions) |
| `build` | Compile release artifact |
| `integration` | End-to-end protocol/API tests |
| `spdx-check` | License header compliance |
| `security` | CodeQL, govulncheck, or equivalent |
| `docker` | Multi-platform container build |
| `docs` | Documentation build (Sphinx, etc.) |

## Automation

- Weekly releases (automated)
- Dependabot / dependency updates: review, don't auto-merge
- Multi-platform testing (amd64, arm64)
- Multi-version testing (Python 3.12+, etc.)
