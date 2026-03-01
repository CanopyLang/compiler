# Plan 23: Documentation Accuracy Audit

**Priority:** LOW
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

Several documentation claims are factually incorrect:

1. **`canopy-core.cabal:12`** claims: *"This package contains no STM/MVar/TVar usage - only pure functional code."*
   - Reality: `Type/Parallel.hs` uses `Control.Concurrent.STM` (TVar) and `Control.Concurrent.Async`. Both `stm` and `async` are listed as build dependencies.

2. **Comments referencing "Elm"** where "Canopy" is correct (covered by Plan 01, but document-only changes here):
   - `Test.hs:235`: "in the Elm report style" → "in the Canopy report style"
   - `Publish.hs:231`: "which should use elm publish" → "canopy publish"
   - `Test/Harness.hs:73`: "DOM shim for Elm runtime" → "Canopy runtime"

3. **`FreeVars = Map Name ()`** comment inconsistency — the type is used as a set but documented/typed as a Map. Either change to `Set Name` or add a clear comment explaining the choice.

4. **`SaveTheEnvironment`** constructor in `AST/Canonical/Types.hs:268` — misleading name for "end of declarations" sentinel. Add a Haddock comment explaining what it actually means.

## Files to Modify

### `packages/canopy-core/canopy-core.cabal`
- Line 12: Remove or correct the "no STM" claim

### `packages/canopy-core/src/AST/Canonical/Types.hs`
- Line 268: Add Haddock to `SaveTheEnvironment`:
  ```haskell
  -- | Sentinel value marking the end of a declaration chain.
  -- Named for historical reasons (inherited from Elm).
  | SaveTheEnvironment
  ```
- Line 314: Add comment to `FreeVars`:
  ```haskell
  -- | Free variables in scope. Uses @Map Name ()@ instead of @Set Name@
  -- for compatibility with existing Map-based operations in the canonicalizer.
  type FreeVars = Map.Map Name.Name ()
  ```

### Various comment fixes
As listed in the Problem section.

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Grep for "no STM" in cabal files — should return zero
4. All Haddock comments are accurate
