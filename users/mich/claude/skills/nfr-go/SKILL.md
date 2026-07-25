---
name: nfr-go
description: Go engineering standards - golangci-lint config, slog logging, table-driven tests, error wrapping, CLI run() pattern, config via env vars. Load before writing, reviewing, or configuring Go code.
---

# Go Standards

## Lints & Formatting

- golangci-lint with staticcheck, gosec, errcheck, gocritic (`.golangci.yml`)
- `go fmt` before every commit (non-negotiable)
- Standard library preferred over external packages; minimal `go.mod`

## Error Handling

- Return `error` from every fallible function; check every error
- Wrap with context: `fmt.Errorf("...: %w", err)`

## Design

- Interfaces for testability
- Context for cancellation and timeouts
- CLI pattern (Mat Ryer): testable `run()` function taking
  `ctx, args, stdout, stderr` — makes the binary testable

## Testing

- Table-driven tests
- `testing.Short()` to separate fast from slow
- Race detector enabled (`-race`)

## Configuration

- Environment variables acceptable as primary config for services
  (12-factor app style)

## Logging

- `log/slog`, structured with fields, JSON handler in production

## Auditing

- `govulncheck` regularly and in CI
