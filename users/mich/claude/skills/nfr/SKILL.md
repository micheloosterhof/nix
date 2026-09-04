---
name: nfr
description: Base engineering standards - language selection, architecture, logging, config, build system, testing, security, licensing, style. The nfr-* domain skills build on this one; load it first, before writing or reviewing code in any language.
---

# Non-Functional Requirements

Personal engineering standards and preferences. These apply across projects
unless a project explicitly overrides them.

Detailed per-domain standards live in skills — load the matching one before
writing, reviewing, or configuring code in that domain: `nfr-rust`,
`nfr-python`, `nfr-go`, `nfr-typescript`, `nfr-frontend`, `nfr-docker`,
`nfr-ci`.

---

## 1. Language Selection

Choose the right tool for the job:

| Domain | Language | Rationale |
|--------|----------|-----------|
| Security-sensitive endpoints, system software | Rust | Memory safety, performance |
| Scripting, protocol emulation, glue code | Python | Rapid iteration, ecosystem |
| Web services, API servers | Go | Simple concurrency, fast compile |
| Frontend | TypeScript (strict) | Type safety in the browser |
| Agent tooling (Claude Code hooks/plugins, MCP servers) | TypeScript (strict) | The agent ecosystem is Node-native |

Never use JavaScript directly. All frontend code is TypeScript.

## 2. Architecture

- **Functional core, imperative shell**: Keep business logic in pure
  functions with no side effects. Push I/O, state mutation, and
  orchestration to the outer edges of the system.
- **Dependency injection**: Accept dependencies (randomness, clock, etc) 
  as parameters rather than constructing them internally. Simplifies
  testing by allowing real collaborators to be replaced without
  mocks. Skip DI when it adds indirection without a testing or
  flexibility benefit (e.g., trivial helpers, scripts with no
  meaningful collaborators).

## 3. Logging

- **Timestamps**: UTC, RFC 3339, with trailing `Z` (e.g., `2026-03-20T14:30:00.000Z`)
- **Format**: Clear text for development, structured JSON for production
- **Multiple targets**: Support stdout + file simultaneously
- **Levels**: TRACE, DEBUG, INFO, WARN, ERROR (no CRITICAL)
- **Per-target filtering**: Each log target can set its own level filter
- **Source attribution**: Include source file + line in structured output
- **No emoticons or decorative characters in log output**
- Per-language libraries: see the `nfr-*` skill for the language.

## 4. Configuration

- **Format**: TOML for config files. Simple, readable, well-specified.
- **Environment variable overrides**: `PREFIX_SECTION__KEY=value` pattern
  (double underscore separates section from key)
- **Env vars take precedence** over file values
- **Glob-loaded configs**: Split large configs into per-service or per-handler
  files loaded from a directory (e.g., `conf/services/*.toml`)
- **No YAML** for application config (YAML is fine for CI/CD where required)

## 5. Build System

Every project gets a Makefile as the single entry point for all operations.
Developers and CI both use the same targets.

**Required targets** (where applicable):

| Target | Purpose |
|--------|---------|
| `build` | Compile / package |
| `test` | Run fast unit tests |
| `test-integration` | Run integration / smoke tests |
| `lint` | Run all linters (ruff, clippy, eslint, etc.) |
| `fmt` | Run formatters |
| `check` | fmt + lint combined |
| `dev` | Start development environment |
| `start` / `stop` | Background service management (PID files) |
| `clean` | Remove build artifacts |
| `docker-build` | Build container image |
| `docker-start` / `docker-stop` | Run/stop container |
| `spdx` | License header compliance check |
| `coverage` | Test coverage report |

**Principles**:
- Targets should be self-documenting (`make help` if complex)
- Use PID files for background process management
- Log output to files for background processes
- Match CI and local workflows (same commands in both)

## 6. Testing

- Tests are mandatory. No feature ships without tests.
- Test real behavior, not mocked behavior. Mocks are a last resort.
- Integration tests use real I/O, real databases, real services.
- All test failures are treated as blockers.
- Test output must be clean (expected errors must be captured and validated).
- Unit tests for every module; integration tests cross-module; smoke tests
  post-deploy; Playwright for UI E2E; security scanning in CI.
- **Coverage**: Track and report, but don't worship a number.
- Per-language frameworks and conventions: see the `nfr-*` skill for the
  language.
- For small CLI programs, have a selftest argument to test itself.
- If deterministic output is available, have externally validated
  input and output as part of the selftest

## 7. Code Quality

Every language gets maximum strictness. Linters run in CI and locally.
Full lint/formatter configs per language live in the `nfr-*` skills.
Non-negotiables that apply even without loading them:

- **Rust**: no `unsafe`, no `.unwrap()` — `?` and explicit error handling
- **Python**: `from __future__ import annotations`, type hints on all
  signatures, no `typing.Any` without justification
- **Go**: `go fmt` before every commit; check every error; wrap with
  `fmt.Errorf("...: %w", err)`
- **TypeScript**: strict mode, no `any`, no direct `console` use

### Pre-commit Hooks

- Enforced, never skipped (`--no-verify` is forbidden)
- Run linters and formatters automatically
- Check for secrets, large files, merge conflicts
- Configured via `.pre-commit-config.yaml` where supported

## 8. Frontend

TypeScript only; Vue (Composition API) or vanilla — avoid React; dark mode
from day one. Browser stack and config: load `nfr-frontend`; the TypeScript
language standards: load `nfr-typescript`.

## 9. Version Control

### Jujutsu & Git

- Jujutsu (`jj`) is the primary VCS, colocated with git for full
  interoperability with git remotes and tooling. Use git directly where
  `jj` is unavailable.
- Main branch: `main` (never `master`)
- **Branching by project maturity**:
  - Mature projects (e.g., Cowrie): PR workflow, no direct commits to `main`
  - Early-stage projects (the current default): commit directly to `main`
  - Big new projects: experimental code on branches, merged to `main` once
    the experiment proves out
- Frequent, small commits — one logical change per commit
- Never `git add -A` without checking `git status` first
- Never skip pre-commit hooks

### Commit Messages

- **Style**: Conventional Commits preferred (`type: description` or
  `type(scope): description`). Imperative descriptive also acceptable.
- **Types**: feat, fix, docs, style, refactor, test, chore, build, ci
- **Imperative mood**: "Add feature" not "Added feature"
- **No emoticons**
- **No AI attribution**: No "Co-Authored-By: Claude", no "Generated with
  Claude Code", no AI tool references anywhere in commits, PRs, or code.
- **Commit author**: Always the human developer

## 10. CI/CD

GitHub Actions is the primary platform, but minimize GitHub-specific
dependencies — tests must run locally via the same tools. Standard job set,
release automation, and matrices: load `nfr-ci`. Containers and deployment
hardening: load `nfr-docker`.

## 11. Licensing & Copyright

Every source file must have an SPDX header:

```
SPDX-FileCopyrightText: <year> <copyright holder>
SPDX-License-Identifier: <license expression>
```

- Use the year the file was created (not updated)
- Config files and non-code: `SPDX-License-Identifier: CC0-1.0`
- Enforce via CI (`reuse lint` or custom `check-spdx.py`)
- Store license texts in `LICENSES/` directory
- License choice: AGPL-3.0 or BSD-3-Clause (depending on project);
  dual licensing (open + commercial) where the business model requires it

## 12. Documentation

### Required Files

| File | Purpose |
|------|---------|
| `README.md` | Project overview, quick start, architecture |
| `SECURITY.md` | Vulnerability reporting, scope, contact |
| `AGENTS.md` | AI agent instructions (project conventions, build, test) |
| `CLAUDE.md` | Points to `@AGENTS.md` (thin wrapper) |
| `CONTRIBUTING.md` | PR guidelines, code style, testing expectations |
| `LICENSE` | Full license text |
| `CHANGELOG.md` | Release notes (if not using GitHub releases) |

### Code Documentation

- **File headers**: Every code file starts with a 2-line `ABOUTME:` comment
  explaining what the file does. Easily greppable across the codebase.
- **Comments explain WHAT and WHY**, not how or history
- **No temporal references** in comments ("new", "old", "refactored", "moved")
- **No AI attribution** in comments
- **Preserve existing comments** unless provably false
- **API docs**: Sphinx (Python), rustdoc (Rust), swag/OpenAPI (Go)

## 13. Dependencies

- **Minimal**: Every dependency is a liability. Justify each one.
- **Prefer standard library** before reaching for external packages
- **Pin versions** in lockfiles (Cargo.lock, package-lock.json, go.sum)
- **Feature-gate** optional functionality (Cargo features, Python extras)
- **Audit regularly**: per-language audit tooling is listed in the
  `nfr-*` skills

## 14. Error Handling

- Per-language patterns: see the `nfr-*` skill for the language.
- **Graceful degradation**: Services handle SIGTERM/SIGINT cleanly.
  Drain connections, flush logs, exit with appropriate code.

## 15. Security

- **SECURITY.md** in every public repository
- **No secrets in code or config files**: Use environment variables
- **Parameterized queries**: No string interpolation in SQL
- **Input validation** at system boundaries (user input, external APIs)
- **XSS prevention**: Sanitize HTML output, use CSP headers
- **Rate limiting** on all public API endpoints
- **Audit logging** for sensitive operations
- **TLS**: Required for production. Minimum TLS 1.2 for real services
  (honeypots intentionally weaken this).
- **RBAC**: Role-based access control for multi-user systems
- **JWT**: Short-lived access tokens, httpOnly refresh cookies
- **Static analysis**: CodeQL or equivalent in CI

## 16. CLI Design

- **Simple**: Minimal flags, sensible defaults
- **Environment variables** for config (not 50 CLI flags)
- **Structured output**: JSON when piped, human-readable when interactive
- **Exit codes**: 0 for success, non-zero for failure
- **No interactive prompts** in automated/CI contexts

## 17. AI Agent Compatibility

Software should be equally usable by humans and AI agents:

- **`AGENTS.md`**: Primary file for AI agent instructions. Contains project
  structure, conventions, build/test commands, and architecture decisions.
- **`CLAUDE.md`**: Thin wrapper that references `@AGENTS.md`. Keep
  Claude-specific overrides minimal.
- **Makefile**: Single entry point that both humans and agents can use
- **Clear error messages**: Agents need parseable output to self-correct
- **No interactive flows** required for build/test/deploy
- **Self-documenting structure**: Conventions should be discoverable from
  the codebase itself (ABOUTME headers, AGENTS.md, consistent naming)

## 18. Style & Tone

- **No emoticons** in code, comments, logs, commit messages, or documentation
- **No AI attribution** anywhere in the project
- **No temporal/historical names**: Never "new", "old", "legacy", "improved"
- **Names describe purpose**, not implementation details
- **Concise writing**: Say it in one sentence, not three
- **Professional tone**: No exclamation marks in code comments or docs
