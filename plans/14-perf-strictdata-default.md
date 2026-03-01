# Plan 14: StrictData as Default Extension

**Priority:** MEDIUM
**Effort:** Medium (1-2 days)
**Risk:** Medium (must audit lazy-by-design types to add `~` annotations)

## Problem

Only 28 out of 443 Haskell source files use the `{-# LANGUAGE StrictData #-}` pragma.
The remaining 415 files default to lazy fields in data types, which causes thunk
accumulation in long-lived data structures (caches, state records, maps of interfaces).

Adding `StrictData` to the `default-extensions` in each `.cabal` file would make all
data type fields strict by default, eliminating space leaks from unevaluated thunks.
Fields that must remain lazy can be annotated with `~` (lazy annotation, available
since GHC 9.2 with `StrictData`).

### Current State

**Files with `StrictData` (28 of 443):**

```
packages/canopy-core/src/AST/Canonical/Types.hs
packages/canopy-core/src/AST/Optimized.hs
packages/canopy-core/src/Canopy/Interface.hs
packages/canopy-core/src/Canonicalize/Expression.hs
packages/canopy-core/src/Canonicalize/Module.hs
packages/canopy-core/src/Generate/JavaScript.hs
packages/canopy-core/src/Generate/JavaScript/Expression.hs
packages/canopy-core/src/Generate/JavaScript/FFI.hs
packages/canopy-core/src/Optimize/DecisionTree.hs
packages/canopy-core/src/Optimize/Expression.hs
packages/canopy-core/src/Optimize/Names.hs
packages/canopy-core/src/Parse/Primitives.hs
packages/canopy-core/src/Reporting/Annotation.hs
packages/canopy-core/src/Type/Constrain/Expression.hs
packages/canopy-core/src/Type/Constrain/Module.hs
packages/canopy-core/src/Type/Constrain/Pattern.hs
packages/canopy-core/src/Type/Instantiate.hs
packages/canopy-core/src/Type/Occurs.hs
packages/canopy-core/src/Type/Solve.hs
packages/canopy-core/src/Type/Type.hs
packages/canopy-core/src/Type/Unify.hs
packages/canopy-builder/src/Builder/Graph.hs
packages/canopy-builder/src/Builder/Hash.hs
packages/canopy-builder/src/Builder/Incremental.hs
packages/canopy-builder/src/Compiler/Cache.hs
packages/canopy-builder/src/Compiler/Types.hs
packages/canopy-driver/src/Driver.hs
packages/canopy-query/src/Query/Engine.hs
```

**Cabal files with default-extensions (none include StrictData):**

All 6 package `.cabal` files and the root `canopy.cabal` share the same
`default-extensions` block, none of which includes `StrictData`:

```
packages/canopy-core/canopy-core.cabal        (line 234)
packages/canopy-builder/canopy-builder.cabal   (line 69)
packages/canopy-terminal/canopy-terminal.cabal (line 185)
packages/canopy-driver/canopy-driver.cabal     (line 39)
packages/canopy-query/canopy-query.cabal       (line 33)
packages/canopy-webidl/canopy-webidl.cabal     (line ~)
canopy.cabal (root)                            (lines 26, 113, 354, 458)
```

### Data Types That Must Remain Lazy

These types intentionally use lazy fields for correctness. With global `StrictData`,
they must add explicit `~` (tilde) annotations:

**1. `Canopy.Data.Bag` (`packages/canopy-core/src/Canopy/Data/Bag.hs`, line 124):**
```haskell
data Bag a
  = Empty
  | One a       -- Must remain lazy: used in foldl' accumulation
  | Two (Bag a) (Bag a)  -- MUST remain lazy: O(1) concatenation depends on it
```

With `StrictData`, `Two` would force both sub-bags on construction, destroying the
O(1) concatenation guarantee and potentially causing stack overflows on deep trees.

**Fix:** Add `~` annotations:
```haskell
data Bag a
  = Empty
  | One a
  | Two ~(Bag a) ~(Bag a)
```

**2. `Canopy.Data.OneOrMore` (`packages/canopy-core/src/Canopy/Data/OneOrMore.hs`, line 124):**
```haskell
data OneOrMore a
  = One a
  | More (OneOrMore a) (OneOrMore a)  -- Same lazy tree pattern as Bag
```

**Fix:**
```haskell
data OneOrMore a
  = One a
  | More ~(OneOrMore a) ~(OneOrMore a)
```

**3. `Type.Constraint` (`packages/canopy-core/src/Type/Type.hs`, line 59):**
Already has `StrictData` at the module level, so no change needed. But the `CLet`
constructor has list and map fields that are already strict under `StrictData`.
The `CAnd [Constraint]` constructor is also strict, which is fine since the list
spine is forced but not the elements.

**4. Parser `State` types (`packages/canopy-core/src/Parse/Primitives.hs`):**
Already has `StrictData`. No change needed.

**5. `Reporting.Result` (CPS newtype):**
This is a newtype wrapping a continuation, so `StrictData` has no effect.

### Types That Benefit Most From StrictData

**AST types without StrictData** -- these hold long-lived data:
- `AST.Source` (all source AST nodes)
- `AST.Canonical` (canonical types module, already has it for Types.hs but not all sub-modules)
- `Canopy.Outline` (project configuration)
- `Canopy.Package` (package metadata)
- `Canopy.Version` (version data)
- `Canopy.ModuleName` (module names)

**Build state types:**
- `Builder.State` (build state accumulator)
- `Builder.LockFile.Types` (lockfile data)

## Solution

### Phase 1: Add StrictData to all cabal default-extensions

Add `StrictData` to the `default-extensions` list in each cabal file. This is a
single-line addition per cabal stanza.

**`packages/canopy-core/canopy-core.cabal` (line 234):**
```yaml
  default-extensions:
      ConstraintKinds
      DataKinds
      ...
      StrictData    -- ADD THIS
      ...
```

Repeat for all 6 package cabal files and all stanzas in `canopy.cabal` (library,
executable, test-suite, benchmark).

### Phase 2: Add lazy annotations to intentionally-lazy types

**`packages/canopy-core/src/Canopy/Data/Bag.hs`:**
```haskell
data Bag a
  = Empty
  | One a
  | Two ~(Bag a) ~(Bag a)
```

**`packages/canopy-core/src/Canopy/Data/OneOrMore.hs`:**
```haskell
data OneOrMore a
  = One a
  | More ~(OneOrMore a) ~(OneOrMore a)
```

### Phase 3: Remove per-file StrictData pragmas

Remove `{-# LANGUAGE StrictData #-}` from all 28 files that currently have it,
since it is now a default extension.

### Phase 4: Compile and fix any breakage

Compile the entire project. `StrictData` can cause:

1. **Infinite loops**: If a type's constructor is used recursively and laziness was
   required (handled in Phase 2 above).
2. **Unnecessary evaluation**: If a field is expensive to compute and was intentionally
   left lazy. Fix by adding `~` annotation.
3. **Bottom propagation changes**: If a field could be `undefined` or `error` and was
   never forced. This would be a latent bug being exposed, not a regression.

Expected breakage should be minimal since most types in the codebase already use
explicit `!` bang patterns on their fields.

## Files to Modify

| File | Change |
|------|--------|
| `canopy.cabal` | Add `StrictData` to all 4 `default-extensions` blocks |
| `packages/canopy-core/canopy-core.cabal` | Add `StrictData` to `default-extensions` |
| `packages/canopy-builder/canopy-builder.cabal` | Add `StrictData` to `default-extensions` |
| `packages/canopy-terminal/canopy-terminal.cabal` | Add `StrictData` to `default-extensions` |
| `packages/canopy-driver/canopy-driver.cabal` | Add `StrictData` to `default-extensions` |
| `packages/canopy-query/canopy-query.cabal` | Add `StrictData` to `default-extensions` |
| `packages/canopy-webidl/canopy-webidl.cabal` | Add `StrictData` to `default-extensions` |
| `packages/canopy-core/src/Canopy/Data/Bag.hs` | Add `~` to `Two` constructor fields |
| `packages/canopy-core/src/Canopy/Data/OneOrMore.hs` | Add `~` to `More` constructor fields |
| 28 files with per-file `StrictData` pragma | Remove the per-file pragma |

## Verification

```bash
# Full build to catch any compilation errors
stack build --fast 2>&1 | head -100

# Run all tests to verify no behavioral changes
make test

# Run property tests (most likely to catch laziness-related issues)
make test-property

# Run benchmarks to measure improvement
stack bench --ba="--match prefix Bench"

# Profile a real build
stack exec -- canopy make +RTS -s -RTS
```

## Expected Impact

- Eliminates thunk accumulation in 415 source files' data types
- Primary benefit in long-lived state: AST nodes, build cache entries, interface maps
- Expected 5-15% reduction in peak memory usage for large projects
- Expected 2-5% improvement in GC pause times (fewer live thunks to traverse)
- Makes the codebase consistently strict, reducing cognitive load about field semantics
