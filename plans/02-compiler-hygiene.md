# Plan 02: Compiler Hygiene

## Priority: CRITICAL — Tier 0
## Effort: 1 week
## Blocks: Public release

## Problem

The compiler has several hygiene issues that must be fixed before any public release:

1. HTTP_DEBUG print statements in production code
2. Broken Makefile targets
3. Dead code and stray files
4. Missing -Wall on some source files
5. CLI grammar errors in user-facing messages

These are not features — they're defects. Fix them fast.

## Tasks

### 1. Remove debug statements (2 hours)

Grep for `HTTP_DEBUG`, `Debug.trace`, `putStrLn` used for debugging, and any `print` statements not behind a proper logging flag. Remove them all.

### 2. Fix Makefile targets (2 hours)

Audit every `make` target. Fix broken ones, remove ones that reference deleted files, ensure `make test`, `make build`, `make clean` all work correctly.

### 3. Remove dead code (4 hours)

- Run the compiler with `-Wall -Werror` and fix every warning
- Remove unused imports, unused bindings, unreachable patterns
- Delete stray files that aren't part of the build

### 4. Add -Wall to all source files (4 hours)

Every `.cabal` file must include `-Wall -Wcompat -Wincomplete-record-updates -Wincomplete-uni-patterns -Wredundant-constraints` in its `ghc-options`. Fix all resulting warnings.

### 5. Fix CLI grammar (2 hours)

Audit all user-facing strings in the terminal package. Fix grammar, spelling, and formatting issues. Canopy's error messages should be exemplary (Elm set this standard — we must meet or exceed it).

### 6. Write README and CONTRIBUTING (4 hours)

- README.md: installation, quick start, architecture overview, link to docs
- CONTRIBUTING.md: development setup, coding standards, PR process, test requirements

## Verification

```bash
make clean && make build  # No warnings
make test                 # All 3,707+ tests pass
grep -r "HTTP_DEBUG" compiler/  # Zero results
grep -r "Debug.trace" compiler/packages/  # Zero results (except test files)
```

## Dependencies

None — this is independent of all other work.
