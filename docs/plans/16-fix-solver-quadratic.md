# Plan 16 — Fix O(n^2) Patterns in Type Solver

**Priority:** Tier 3 (Performance)
**Effort:** 1 day
**Risk:** Medium (touching the type solver requires careful testing)
**Files:** `packages/canopy-core/src/Type/Solve.hs`

---

## Problem

Three O(n^2) patterns in the type solver:

### 1. `elem` on list (line 662)

```haskell
name `elem` newVarsThisLevel
```

`newVarsThisLevel` is `[Name.Name]` built from `Map.keys`. `elem` is O(N) linear scan. Called inside `forM (Map.toList finalMonoEnv)`, making the total O(|finalMonoEnv| x |newVarsThisLevel|).

### 2. `extractTypeVars` accumulation (lines 733-762)

```haskell
-- In foldM:
acc <> vars  -- list concatenation
```

`<>` on lists is `++` which is O(N) for the left operand. In a left fold, this produces O(N^2) total allocation.

### 3. `deepCloneVariable` (lines 425-449)

Called once per branch x per polymorphic function. For 20 polymorphic functions and a 10-arm case, that's 200 full deep clones.

## Implementation

### Fix 1: Replace `elem` with `Set.member`

```haskell
-- Before:
let newVarsThisLevel = Map.keys someMap
... name `elem` newVarsThisLevel ...

-- After:
let newVarsThisLevelSet = Map.keysSet someMap  -- Set Name.Name
... Set.member name newVarsThisLevelSet ...
```

This changes O(N) per lookup to O(log N).

### Fix 2: Replace list concatenation with difference list or Seq

```haskell
-- Before (in foldM):
foldM (\acc var -> do
  vars <- extractVarsFromType var
  pure (acc <> vars)
) [] allVars

-- After (using Data.Sequence for efficient append):
import qualified Data.Sequence as Seq

foldM (\acc var -> do
  vars <- extractVarsFromType var
  pure (acc Seq.>< Seq.fromList vars)
) Seq.empty allVars
-- Then: toList result

-- Or simpler: use concatMap pattern
vars <- traverse extractVarsFromType allVars
let allExtracted = concat vars
```

The `concat` approach is simpler and O(total_elements) rather than O(N^2).

### Fix 3: Optimize deepCloneVariable

This is the most complex fix. Options:

**Option A: Lazy cloning (clone on demand)**

Instead of eagerly cloning the entire type structure for each branch, create a "snapshot" marker. When a variable is first mutated in a branch, copy-on-write from the snapshot.

This is a larger architectural change and may not be worth the complexity.

**Option B: Share identical clones**

If the same polymorphic function appears in multiple case branches with the same instantiation, reuse the clone. Add a `Map Variable Variable` memoization table to `deepCloneVariable`:

```haskell
deepCloneVariable :: IORef (Map Variable Variable) -> Variable -> IO Variable
deepCloneVariable memoRef var = do
  memo <- readIORef memoRef
  case Map.lookup var memo of
    Just clone -> pure clone
    Nothing -> do
      clone <- actuallyClone var
      modifyIORef' memoRef (Map.insert var clone)
      pure clone
```

**Option C: Reduce clone scope**

Only clone variables that are actually used in each branch, not all polymorphic variables in scope. This requires tracking which variables each branch references, which the constraint generator already knows.

**Recommended:** Start with Options A/B for the biggest win with least risk. Option C requires deeper constraint-generator changes.

### Fix 4: Investigate solveCaseBranchesIsolated

The dead `solveCaseBranchesIsolated` function (Plan 03) may have been the intended optimization for case branch isolation. If it implements a better strategy than deep cloning, wire it in. If it's buggy, document why and delete.

## Validation

```bash
make build && make test
```

Additionally, create a stress test module with:
- 50 let bindings
- 10-arm case expression
- 20 polymorphic helper functions in scope

Compare type-check time before/after:

```bash
time canopy check stress-test.can  # Before
# Apply fixes
time canopy check stress-test.can  # After
```

## Acceptance Criteria

- Zero `elem` on plain lists in `Solve.hs` — all replaced with `Set.member`
- Zero `acc <> vars` list concatenation in folds — replaced with `concat` or `Seq`
- `deepCloneVariable` optimized (memoization or scope reduction)
- `make build && make test` passes
- No type-checking regression on existing test suite
