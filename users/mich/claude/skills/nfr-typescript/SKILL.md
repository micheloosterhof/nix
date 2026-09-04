---
name: nfr-typescript
description: TypeScript engineering standards - strict-mode config, eslint/prettier rules, logging, dependency minimalism. Load before writing, reviewing, or configuring any TypeScript code - agent tooling, MCP servers, Node CLIs, or the browser (for browser stack choices also load nfr-frontend).
---

# TypeScript Standards

Language standards for all TypeScript, wherever it runs — browser code,
agent tooling (Claude Code hooks and plugins, MCP servers), and Node CLIs.
Browser stack choices (Vite/Vue/Tailwind) live in `nfr-frontend`.

## Language & Tooling

- TypeScript only — no `.js` files in `src/`
- TypeScript strict mode enabled
- Minimal runtime dependencies: <10 production deps

## Lints & Formatting

- eslint strict: `no-explicit-any: error`, `no-console: warn` (use the
  project logger), `eqeqeq: always`, prefer `const`
- prettier (`eslint.config.js` for lint config)

## Logging

- Minimal custom logger (console-based, debug toggle)
