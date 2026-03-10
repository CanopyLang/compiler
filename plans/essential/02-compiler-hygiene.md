# Plan 02: Compiler Hygiene

## Priority: CRITICAL — Tier 0
## Status: MOSTLY COMPLETE — needs final verification
## Effort: 2-3 days remaining (verification + any remaining -Wall fixes)
## Blocks: Public release

> **Status Update (2026-03-07 audit):** Most hygiene items are done:
>
> - [x] `HTTP_DEBUG` — zero occurrences remain in compiler/packages/
> - [x] `Debug.trace` — zero occurrences in production code
> - [x] Makefile — exists at `compiler/Makefile` with comprehensive targets (build, test,
>   test-unit, test-property, test-integration, test-watch, test-coverage, test-coverage-check,
>   test-coverage-report, test-coverage-badge)
> - [x] README.md — exists at `compiler/README.md`
> - [x] CONTRIBUTING.md — exists at `compiler/CONTRIBUTING.md`
>
> Remaining verification needed:
> - [ ] Confirm all `.cabal` files have `-Wall` in ghc-options
> - [ ] Confirm zero warnings when building with `-Wall -Werror`
> - [ ] Audit CLI grammar in user-facing strings
> - [ ] Verify all Makefile targets work correctly

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
