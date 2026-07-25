---
name: nfr-frontend
description: Frontend engineering standards - Vite/Vue/Pinia stack, eslint/prettier strictness, Tailwind, OpenAPI clients, Playwright/Lighthouse. Load before writing, reviewing, or configuring frontend/TypeScript code.
---

# Frontend Standards

## Stack

- Build tool: Vite
- TypeScript only — no `.js` files in `src/`
- UI: Vue with Composition API or vanilla; avoid React. Prefer lightweight
  component libraries (Element Plus) over heavy frameworks.
- State management: Pinia (Vue projects)
- Styling: Tailwind CSS preferred; CSS variables for theming
- API client: type-safe, generated from OpenAPI spec (openapi-fetch)
- Routing: lazy-loaded routes
- Dark mode from day one
- Minimal runtime dependencies: <10 production deps
- No emoticons in UI text (icons fine, emoji in strings not)

## Lints & Formatting

- eslint strict: `no-explicit-any: error`, `no-console: warn` (use the
  project logger), `eqeqeq: always`, prefer `const`
- TypeScript strict mode enabled
- prettier (`eslint.config.js` for lint config)

## Error Handling

- API client returns `{data, error}` tuples — never throws
- Display user-friendly messages, log technical details

## Logging

- Minimal custom logger (console-based, debug toggle)

## Testing & Performance

- E2E: Playwright
- Lighthouse audits in CI
