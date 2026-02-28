# Plan 35: Native Test Framework Enhancement

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Low — extends existing test infrastructure

## Problem

The test framework exists (TestMain variant, test harness, DOM shim) but lacks features expected by users:
- No built-in assertion library
- No describe/it structure
- No test filtering by name
- No watch mode for tests
- No coverage reporting per Canopy module

### Key Files
- `packages/canopy-terminal/src/Test.hs` — test dispatch
- `packages/canopy-terminal/src/Test/Harness.hs` — JS test harness
- `core-packages/test/src/` — test library source

## Implementation Plan

### Step 1: Enhance core test library

**File**: `core-packages/test/src/Test.can`

Add assertion functions:
```elm
equal : a -> a -> Expectation
notEqual : a -> a -> Expectation
isTrue : Bool -> Expectation
isFalse : Bool -> Expectation
contains : String -> String -> Expectation
throws : (() -> a) -> Expectation
```

### Step 2: Add describe/it structure

```elm
suite : Test
suite =
    describe "Math operations"
        [ test "addition" <|
            \() -> equal (1 + 1) 2
        , test "multiplication" <|
            \() -> equal (2 * 3) 6
        , describe "negative numbers"
            [ test "negate" <|
                \() -> equal (negate 5) -5
            ]
        ]
```

### Step 3: Test filtering

Add `--filter` flag to `canopy test`:

```bash
canopy test --filter "Math operations"
canopy test --filter "addition"
```

### Step 4: Watch mode for tests

Add `--watch` flag that re-runs tests on file changes:

```bash
canopy test --watch
# Watches src/ and tests/ for changes
# Re-runs only affected tests
```

### Step 5: Test output formatting

Support multiple output formats:
- `--reporter=dots` (default) — compact dot output
- `--reporter=spec` — describe/it tree with results
- `--reporter=json` — machine-readable for CI
- `--reporter=junit` — JUnit XML for CI integration

### Step 6: Tests

- Test assertion functions
- Test describe/it nesting
- Test filtering
- Test reporter output formats

## Dependencies
- None
