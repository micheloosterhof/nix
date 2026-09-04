---
name: nfr-frontend
description: Frontend engineering standards - Vite/Vue/Pinia stack, Tailwind, OpenAPI clients, Playwright/Lighthouse. Load before writing, reviewing, or configuring browser frontend code, together with nfr-typescript for the language standards.
---

# Frontend Standards

Browser stack standards. The TypeScript language layer (strict mode,
eslint/prettier, logging) lives in `nfr-typescript` — load both.

## Stack

- Build tool: Vite
- UI: Vue with Composition API or vanilla; avoid React. Prefer lightweight
  component libraries (Element Plus) over heavy frameworks.
- State management: Pinia (Vue projects)
- Styling: Tailwind CSS preferred; CSS variables for theming
- API client: type-safe, generated from OpenAPI spec (openapi-fetch)
- Routing: lazy-loaded routes
- Dark mode from day one
- No emoticons in UI text (icons fine, emoji in strings not)

## Error Handling

- API client returns `{data, error}` tuples — never throws
- Display user-friendly messages, log technical details

## Testing & Performance

- E2E: Playwright
- Lighthouse audits in CI
