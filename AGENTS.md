# Repository Guidelines

Use this guide to contribute efficiently to the Canopy CLI/ compiler repository.

## Project Structure & Module Organization

- `compiler/src/`: Core language modules (AST, Parse, Type, Generate, Reporting).
- `builder/src/`: Build orchestration, dependency solving, packaging, logging.
- `terminal/src/`: End‑user CLI commands (e.g., `Make`, `Repl`, `Develop`).
- `terminal/impl/`: Terminal helpers and error handling.
- `test/`: Tasty test tree organized by `Unit/`, `Property/`, `Integration/`, `Golden/`.
- Top‑level config: `stack.yaml`, `package.yaml`, `canopy.cabal`, `hie.yaml`, `Makefile`.

## Build, Test, and Development Commands

- Build CLI: `make build` (uses `stack install --fast --pedantic`).
- Clean: `stack clean`.
- All tests: `make test` or `stack test`.
- Focused tests: `make test-unit` | `make test-property` | `make test-integration`.
- Watch tests: `make test-watch`.
- Coverage: `make test-coverage` (HPC report under `.stack-work/install/*/doc/`).
- Format: `make format` (Ormolu over `src/` and `test/`).
- Lint/fix: `make fix-lint` (HLint refactors, then format).

## Coding Style & Naming Conventions

- Formatter: Ormolu (required). Run before commits: `make format`.
- Lint: HLint; prefer automatic refactors via `make fix-lint`.
- Haskell style: modules `CamelCase` (e.g., `Data.Name`), functions `camelCase`, types `CamelCase`, constants/newtypes `CamelCase`, records with descriptive fields.
- Avoid partial functions; prefer total functions and explicit error types in `Reporting.*`.

## Testing Guidelines

- Framework: Tasty (+ HUnit, QuickCheck, Golden). See `TESTING.md` for examples.
- Layout: mirror source tree under `test/Unit`, `test/Property`, etc.
- Patterns: group tests by module (e.g., `Unit/Data/NameTest.hs`).
- Run locally with `make test` and add coverage for core modules.

## Commit & Pull Request Guidelines

- Commits: imperative, concise subject (≤72 chars), scoped when helpful.
  - Example: `Parse: fix number literal with underscores`.
- PRs: include purpose, approach, risk, and testing notes; link issues.
- Checks: CI must pass (`.github/workflows`), code formatted/linted, tests added or updated.
- Screenshots/logs: paste CLI output for new commands or error messages.

## CI, Tooling, and Editor Setup

- CI runs `stack build/test` across OSes and uploads coverage.
- Use HLS with `hie.yaml` for local diagnostics.
- Prefer `stack` for reproducible builds; GHC 9.8.4 per CI matrix.

