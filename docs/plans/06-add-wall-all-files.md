# Plan 06 — Add -Wall to All Source Files

**Priority:** Tier 1 (Critical Architecture)
**Effort:** 1 day
**Risk:** Medium (may surface many new warnings that need fixing)
**Files:** 29+ files in `packages/canopy-core/src/`

---

## Problem

29 source files in `canopy-core/src/` lack `{-# OPTIONS_GHC -Wall #-}`. Without this pragma, GHC cannot warn about non-exhaustive pattern matches, unused bindings, missing fields, or redundant guards. The most critical omissions are:

- `Generate/JavaScript/Expression.hs` (1,144 lines of codegen)
- `Generate/JavaScript.hs` (1,050 lines of codegen)
- `Type/UnionFind.hs` (mutable core of the type solver)
- All `Data/*` modules (13 files)
- `Generate/Html.hs`, `Generate/Mode.hs`, `Generate/JavaScript/Functions.hs`

## Files Missing -Wall

```
packages/canopy-core/src/Canopy/Magnitude.hs
packages/canopy-core/src/Canopy/ModuleName.hs
packages/canopy-core/src/Data/Index.hs
packages/canopy-core/src/Data/Map/Utils.hs
packages/canopy-core/src/Data/Name/Constants.hs
packages/canopy-core/src/Data/Name/Core.hs
packages/canopy-core/src/Data/Name/Generation.hs
packages/canopy-core/src/Data/Name.hs
packages/canopy-core/src/Data/Name/Kernel.hs
packages/canopy-core/src/Data/Name/TypeVariable.hs
packages/canopy-core/src/Data/NonEmptyList.hs
packages/canopy-core/src/Data/Utf8/Binary.hs
packages/canopy-core/src/Data/Utf8/Builder.hs
packages/canopy-core/src/Data/Utf8/Core.hs
packages/canopy-core/src/Data/Utf8/Creation.hs
packages/canopy-core/src/Data/Utf8/Encoding.hs
packages/canopy-core/src/Data/Utf8.hs
packages/canopy-core/src/Data/Utf8/Manipulation.hs
packages/canopy-core/src/Data/Utf8/Types.hs
packages/canopy-core/src/Generate/Html.hs
packages/canopy-core/src/Generate/JavaScript/Expression.hs
packages/canopy-core/src/Generate/JavaScript/Functions.hs
packages/canopy-core/src/Generate/JavaScript.hs
packages/canopy-core/src/Generate/Mode.hs
packages/canopy-core/src/Nitpick/Debug.hs  (deleted in Plan 03)
packages/canopy-core/src/Reporting/Error/Import.hs
packages/canopy-core/src/Reporting/Exit/Help.hs
packages/canopy-core/src/Reporting/Report.hs
packages/canopy-core/src/Type/UnionFind.hs
```

## Implementation

### Step 1: Add pragma to each file

For each file, add at the top of the module (after LANGUAGE pragmas, before module declaration):

```haskell
{-# OPTIONS_GHC -Wall #-}
```

### Step 2: Build and collect warnings

```bash
stack build canopy-core 2>&1 | tee /tmp/wall-warnings.txt
grep "warning:" /tmp/wall-warnings.txt | sort | uniq -c | sort -rn
```

### Step 3: Fix warnings by category

**Priority order for fixing warnings:**

1. **Non-exhaustive patterns** — These are potential runtime crashes. Add missing cases or use wildcard with `InternalError.report`.

2. **Unused bindings** — Remove the binding or prefix with `_` if intentionally unused.

3. **Missing signatures** — Add type signatures to top-level bindings.

4. **Redundant constraints** — Remove unused class constraints.

5. **Name shadowing** — Rename the inner binding. Do NOT add `-fno-warn-name-shadowing`.

### Step 4: Address existing warning suppressions

Review and minimize existing suppressions in files that already have `-Wall`:

- `Json/Decode.hs`: `-fno-warn-unused-do-bind` — investigate each unused bind. If the result truly doesn't matter, use `void` or `_ <-`. Remove the suppression.
- `Parse/Primitives.hs`: `-fno-warn-noncanonical-monad-instances` — if the instances are noncanonical, fix them. Remove the suppression.
- `Type/Solve.hs`: `-Wno-unused-top-binds` — investigate what is unused (likely `solveCaseBranchesIsolated` from Plan 03). Either wire it in or delete it. Remove the suppression.

### Step 5: Verify zero warnings

```bash
stack build canopy-core --pedantic 2>&1 | grep -c "warning:"
# Should output: 0
```

The `--pedantic` flag in the Makefile's `build` target already treats warnings as errors. Once all warnings are fixed, the build will enforce zero-warning going forward.

## Validation

```bash
make build  # --pedantic is already in Makefile, will fail on warnings
make test   # All 2,376 tests must pass
```

## Acceptance Criteria

- Every `.hs` file in `packages/canopy-core/src/` has `{-# OPTIONS_GHC -Wall #-}`
- `stack build canopy-core --pedantic` produces zero warnings
- No new `-fno-warn-*` suppressions added (existing ones removed or justified)
- `make build && make test` passes
