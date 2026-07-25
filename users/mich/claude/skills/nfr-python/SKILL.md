---
name: nfr-python
description: Python engineering standards - ruff/mypy config, typing, testing with pytest/tox, packaging with pyproject/setuptools-scm, logging. Load before writing, reviewing, or configuring Python code.
---

# Python Standards

## Lints & Typing

- ruff for linting AND formatting; strict rule set: A, B, E, F, I, UP,
  T20, Q, RUF, TC, TRY, PYI
- mypy with gradually increasing strictness
- `from __future__ import annotations` in every file
- Type hints on all function signatures
- No `typing.Any` without justification

## Error Handling

- Explicit exception types. Catch at boundaries, let propagate internally.
- Type-hint exceptions where possible

## Testing

- `tests/` directory with pytest; `conftest.py` for shared fixtures
- `tox` as the test runner to standardize environments
- CI matrix: multiple Python versions (3.12+), amd64 + arm64

## Packaging

- `pyproject.toml` with `setuptools` + `setuptools-scm` for version
  management from git tags
- `src/` layout
- Exact versions in requirements for reproducibility

## Logging

- stdlib `logging` (with custom bridges as needed)

## Auditing

- `safety` regularly and in CI
