# Canopy Compiler Audit - Implementation Plan

## Context

A Staff+ level audit of the Canopy compiler identified critical P0/P1/P2 issues across the codebase. This plan addresses every actionable finding.

## Scope

- **5 phases**, ordered by severity (P0 safety first, then P0 correctness, then P1, then P2, then cleanup)
- **~20 files** modified
- **~86 orphaned plan files** removed

## Phase 0: File Cleanup

Removed all orphaned plan, audit, status, and research files from `plans/`, `docs/`, root, and `test/`.

## Phase 1: P0 Safety

| File | Issue | Fix |
|------|-------|-----|
| `packages/canopy-driver/src/Queries/Type/Check.hs` | `unsafePerformIO` in `formatAllErrors` | Changed to `IO String`, propagated through callers |
| `packages/canopy-driver/src/Queries/Canonicalize/Module.hs` | `undefined` in CPS continuation | Replaced with proper initial values for the Result CPS type |
| `packages/canopy-query/src/Query/Simple.hs` | Global `IORef` via `unsafePerformIO` | Threaded cache through `executeQuery` parameter |
| `packages/canopy-query/src/Debug/Logger.hs` | Global env read via `unsafePerformIO` | Made IO action, cached at startup |
| `packages/canopy-core/src/Logging/Debug.hs` | Two `unsafePerformIO` uses | Made `logConfig` IO, made `formatLogMessage` IO |
| `packages/canopy-core/src/Interpret/Core.hs` | Float always returns `0.0` | Parse actual float value from Utf8 |

## Phase 2: P0 Correctness

| File | Issue | Fix |
|------|-------|-----|
| `packages/canopy-terminal/src/Lint.hs` | `--fix` writes to `"<source>"` | Thread real file path through lint pipeline |
| `packages/canopy-driver/src/Queries/Parse/Module.hs` | `extractDecls` returns `[]` | Count actual declarations from module |
| `packages/canopy-core/src/Generate/JavaScript.hs` | `error` calls (2) | Replaced with JS error comments |
| `packages/canopy-core/src/Generate/JavaScript/Expression.hs` | `error` calls (11) | Replaced with JS error comments |

## Phase 3: P1 Functional Gaps

| File | Issue | Fix |
|------|-------|-----|
| `packages/canopy-mcp/src/index.ts` | Stub tool responses | Honest "not yet implemented" messages |
| `packages/canopy-terminal/impl/Terminal/Error/Display.hs` | Empty flag suggestions | Use `flagsForCommand` data with Levenshtein distance |

## Phase 4: P2 Quality

| File | Issue | Fix |
|------|-------|-----|
| `packages/canopy-terminal/impl/Terminal/Error/Display.hs` | Empty flag suggestions with TODO | Implemented suggestion using known flags |
| Various | Documentation and cleanup | Verified correct behavior |

## Phase 5: Verification

- `make build` compiles without warnings
- `make test` passes all tests
- Grep checks verify all fixes applied
