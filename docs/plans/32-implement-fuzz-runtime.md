# Plan 32 — Implement Fuzz Testing Runtime

**Priority:** Tier 6 (Strategic)
**Effort:** 3 days
**Risk:** Medium
**Files:** `core-packages/test/src/Test.can`, `core-packages/test/src/Fuzz.can`, `packages/canopy-terminal/src/Test.hs`, JS runtime files

---

## Problem

The fuzz testing infrastructure exists as types but is not functional:

- `Fuzz.can` defines `Fuzzer a = Fuzzer` — a stub type with no actual generation
- `Test.can` defines `FuzzTest description` — but `runToRunnerResults` returns `"FUZZ_TEST (requires fuzzer)"` without execution
- The `fuzz` function produces a `FuzzTest` node but the test runner skips it

Elm's `elm-explorations/test` has a fully working shrinking fuzzer. Canopy's is vapor.

## Design

### Fuzzer Architecture

```canopy
type Fuzzer a =
  { generate : Seed -> (a, Seed)
  , shrink : a -> List a
  , toString : a -> String
  }
```

The fuzzer is a record with:
- **generate**: PRNG-based value generation from a seed
- **shrink**: produces simpler values for counterexample minimization
- **toString**: renders values for error messages

### Built-in Fuzzers

```canopy
int : Fuzzer Int
int = { generate = randomInt, shrink = shrinkInt, toString = String.fromInt }

string : Fuzzer String
string = { generate = randomString, shrink = shrinkString, toString = identity }

list : Fuzzer a -> Fuzzer (List a)
list inner = { generate = randomList inner, shrink = shrinkList inner, toString = ... }
```

### Test Runner Integration

When the test runner encounters a `FuzzTest`:
1. Generate 100 random inputs (configurable via `--fuzz-runs`)
2. Run the property on each input
3. On failure, shrink the counterexample (up to 100 shrink steps)
4. Report the minimal counterexample

## Implementation

### Step 1: Implement Fuzzer type and built-in fuzzers in Canopy

Replace the stub `Fuzz.can` with actual generation/shrink implementations. This requires:
- A PRNG (linear congruential or xorshift) implemented in Canopy
- Shrink functions for each base type
- Combinators: `map`, `andThen`, `pair`, `triple`, `oneOf`, `frequency`

### Step 2: Implement fuzz execution in the test harness

In `Test.hs`, replace the `FuzzTest` skip with actual execution:

```haskell
executeFuzzTest :: FuzzConfig -> FuzzTest -> IO TestResult
executeFuzzTest config test = do
  seed <- maybe randomSeed pure (config ^. fuzzSeed)
  results <- forM [1..config ^. fuzzRuns] $ \i ->
    generateAndTest seed i
  case findFailure results of
    Nothing -> pure (Pass (config ^. fuzzRuns) "passed")
    Just (input, _) -> do
      shrunk <- shrinkCounterexample input
      pure (Fail (renderCounterexample shrunk))
```

### Step 3: Add CLI flags

```
--fuzz-runs N     Number of fuzz iterations (default: 100)
--fuzz-seed S     PRNG seed for reproducibility
```

### Step 4: Implement in JavaScript runtime

The fuzzer logic runs as Canopy code compiled to JS. The test harness just invokes the compiled `fuzz` test and reads the result through the NDJSON protocol.

## Validation

```bash
make build && make test

# Create a fuzz test:
cat > test/FuzzExample.can << 'EOF'
module FuzzExample exposing (..)

import Test exposing (Test, fuzz)
import Fuzz

suite : Test
suite =
  fuzz Fuzz.int "integers are not negative" <|
    \n -> n >= 0  -- This should fail with a negative counterexample
EOF

canopy test test/FuzzExample.can
# Should report: FAIL with counterexample like -1
```

## Acceptance Criteria

- `fuzz` tests actually execute with random inputs
- Counterexample shrinking produces minimal failing inputs
- `--fuzz-runs` and `--fuzz-seed` CLI flags work
- Built-in fuzzers: `int`, `float`, `string`, `bool`, `list`, `maybe`, `pair`
- `make build && make test` passes
