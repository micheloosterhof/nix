---
name: nfr-rust
description: Rust engineering standards - clippy/rustfmt config, error handling, testing conventions, workspace layout, logging, packaging. Load before writing, reviewing, or configuring Rust code.
---

# Rust Standards

## Lints & Formatting

- `unsafe_code = "deny"` — no unsafe anywhere
- `clippy::all = "deny"`, `clippy::pedantic = "warn"`
- `clippy::unwrap_used = "deny"` — use `?` or explicit error handling
- rustfmt with `.rustfmt.toml`
- Edition: latest stable (currently 2024)

## Error Handling

- `Result<T, Error>` everywhere; `?` propagation
- Custom `Error` enum per crate + `Result<T>` alias at project level
- Never `.unwrap()`

## Testing

- Inline `#[cfg(test)] mod tests` in each file
- Integration tests: one test per file when global state requires process
  isolation

## Workspace & Packaging

- Cargo workspace for multi-crate projects
- Pin dependency versions in `workspace.dependencies` so all crates share
  the same versions

## Logging

- `tracing` + `tracing-subscriber` (json, env-filter features)

## Auditing

- `cargo-audit` regularly and in CI
