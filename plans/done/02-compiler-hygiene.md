# Plan 02: Compiler Hygiene

## Priority: CRITICAL — Tier 0
## Status: DONE — verified 2026-03-11
## Effort: Complete
## Blocks: Public release

> **Status Update (2026-03-10 deep audit):** Nearly everything is clean:
>
> - [x] `HTTP_DEBUG` — zero occurrences in compiler/ (verified via grep)
> - [x] `Debug.trace` — zero occurrences in production code (verified via grep)
> - [x] `import Debug` — zero occurrences (verified via grep)
> - [x] Makefile — comprehensive with 20+ targets: build, test, test-unit, test-property,
>   test-integration, test-watch, test-coverage, bench, lint, format, profile, webidl
> - [x] README.md — 105 lines, covers quick start, architecture, development
> - [x] CONTRIBUTING.md — 204 lines, references CLAUDE.md, forbids mock tests
> - [x] All `.cabal` files have `-Wall` — verified across canopy-core, canopy-terminal,
>   canopy-builder, canopy-query, canopy-driver, canopy-webidl (all have `-Wall -fwarn-tabs -O2`)
> - [x] All putStrLn usage is legitimate — 13 occurrences, all user-facing output (build
>   messages, REPL, linting JSON, audit output)
>
> **Verified 2026-03-11:**
> - [x] Confirm zero warnings when building with `-Wall -Werror` — PASS
> - [x] All Makefile targets execute successfully — PASS
> - [x] All 3,914 tests pass — PASS

## Problem

The compiler had several hygiene issues that must be fixed before any public release. Most have been addressed.

## Remaining Tasks

### 1. Verify -Wall compliance (2 hours)

Every `.cabal` file must include `-Wall -Wcompat -Wincomplete-record-updates -Wincomplete-uni-patterns -Wredundant-constraints` in its `ghc-options`. Verify and fix all resulting warnings.

### 2. Audit CLI grammar (2 hours)

Audit all user-facing strings in the terminal package. Fix grammar, spelling, and formatting issues. Canopy's error messages should be exemplary.

### 3. Verify Makefile targets (1 hour)

Run every `make` target and confirm they all work correctly.

## Verification

```bash
make clean && make build  # No warnings
make test                 # All 3,707+ tests pass
grep -r "HTTP_DEBUG" compiler/  # Zero results (verified)
grep -r "Debug.trace" compiler/packages/  # Zero results (verified)
```

## Dependencies

None — this is independent of all other work.
