# Test Validation & Repair Prompt — Canopy Compiler Coding Guidelines (Non-Negotiable)

**Task:**

- Validate and, if necessary, **repair and extend** the tests for the module: `$ARGUMENTS`.
- Start by locating **all existing tests** for this module across:
  - `test/Unit`
  - `test/Property`
  - `test/Golden`
  - `test/Integration`
- Also look in the folders that are nested for this module for example Main.hs also look in Main/\*.hs
- Ensure every test **complies with CLAUDE.md**, is **useful** (asserts real behavior and exact outcomes), and achieves **≥80% coverage** for the target module.
- Iterate: **audit → fix → add → re-run** until all standards are met.
- Use **Haskell Tasty** and follow the style of `test/Unit/Parse/PatternTest.hs`.

---

## Validation Scope & Architecture

### Where to Look

- **Unit tests**: `test/Unit/<ModulePath>Test.hs`
- **Property tests**: `test/Property/<ModulePath>Props.hs`
- **Golden tests**: `test/Golden/<ModulePath>Golden.hs`
- **Integration tests**: `test/Integration/<Feature>Test.hs`

### What “Useful” Means

- Tests **assert expected outcomes** of functions, not tautologies or reflexive comparisons.
- Tests cover **success** and **error** paths, **edge cases**, and **boundary values**.
- **Exact values** are asserted (strings, structures, error types), not partial/contains unless strictly necessary.

---

## Steps

1. **Discover & Collect**

   - Find all tests referencing the module:
     ```bash
     grep -R "ModuleName" test/ || true
     ```
   - List uncovered files (after a first run) with coverage report paths.

2. **Compliance Audit (CLAUDE.md)**

   - Check imports: **types unqualified; functions qualified**, meaningful aliases only.
   - Check function size (≤15 lines), ≤4 parameters, ≤4 branching points.
   - Verify lenses used in any record setup within tests (no record-dot syntax).
   - Ensure tests are organized in small, focused helpers rather than long monoliths.
   - Confirm Haddock header in each test module describing **purpose** and **scope**.

3. **Usefulness Audit**

   - Flag and remove/replace **forbidden patterns** (see Anti-Fake Testing Rules below).
   - Replace “weak” assertions with **exact** value checks.
   - Ensure negative/error cases exist and assert **precise** error constructors/messages.
   - Add boundary tests (empty, singleton, max/min sizes, unusual Unicode, etc.).

4. **Refactor Existing Tests**

   - Split oversized tests into smaller helpers to meet complexity/size limits.
   - Normalize imports to **CLAUDE.md** standard.
   - Replace ad-hoc generators with **QuickCheck** generators and **shrinkers** where relevant.
   - Deduplicate setup using helpers; keep each test ≤15 lines.

5. **Add Missing Tests**

   - **Unit**: each public function gets at least one **success** and one **failure**/edge-case test.
   - **Property**: round-trip, invariants, and laws (only if they reflect **module semantics**, not generic Haskell correctness).
   - **Golden**: for stable textual/JS/AST/pretty-print outputs (place fixtures in `test/Golden/expected` and `test/Golden/sources`).
   - **Integration**: cross-module workflows and error propagation.

6. **Run & Iterate**

   - Validate locally:
     ```bash
     make lint
     make format
     make test
     make test-coverage
     ```
   - If coverage <80% or checks fail, **return to Step 3** and iterate until satisfied.

7. **Flakiness & Robustness**

   - Re-run suspicious tests multiple times:
     ```bash
     make test-match PATTERN="ModuleName" && make test-match PATTERN="ModuleName"
     ```
   - For properties, increase iterations on failure and add **shrinking** to produce minimal counterexamples.

8. **Registration**

   - Ensure new test modules are exported and registered in `test/Main.hs` under the proper group (Unit/Property/Golden/Integration).

9. **Commit (Conventional Commits)**
   - Prepare a precise message:
     ```
     test(ModuleName): validate, repair, and extend tests to meet CLAUDE.md and ≥80% coverage
     ```
   - Include bullet points summarizing fixes and new cases.

---

## Anti-Fake Testing Rules

### ❌ FORBIDDEN (replace with meaningful assertions)

- Reflexive equality: `x @?= x`
- Meaningless distinctness: `a /= b` for unrelated constants
- “Non-empty show” checks
- Loose substring checks for structured output
- Hand-rolled “always true/false” mocks or placeholders

### ✅ REQUIRED (examples)

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for <ModuleName>.
--   Verifies exact outputs, errors, and edge cases.
module Unit.<ModulePath>Test (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty, (===), (==>))

-- Types unqualified, functions qualified (CLAUDE.md)
import qualified <Project>.<ModuleName> as Mod
import qualified Data.Text as Text

tests :: TestTree
tests =
  testGroup "ModuleName"
    [ testCase "toChars exact" $
        Mod.toChars (Mod.fromChars "hi") @?= "hi"
    , testProperty "roundtrip from/to" $ \s ->
        let t = Text.pack s
        in Mod.toChars (Mod.fromChars t) === t
    ]
```
