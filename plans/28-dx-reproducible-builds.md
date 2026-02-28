# Plan 28: Reproducible Build Verification

## Priority: HIGH
## Effort: Medium (1-2 days)
## Risk: Low — verification layer on top of existing build

## Problem

The lock file (Plan 01-14 area) enables reproducible builds in theory, but there's no verification that builds are actually reproducible. Non-determinism can creep in through:
- Timestamp-dependent code generation
- Map iteration order in codegen
- Floating point formatting differences
- System-dependent path separators in output

## Implementation Plan

### Step 1: Add --verify-reproducible flag

**File**: `packages/canopy-terminal/src/Make.hs`

Add `--verify-reproducible` flag that builds twice and compares output:

```haskell
verifyReproducible :: FilePath -> IO (Either ReproError ())
verifyReproducible root = do
  output1 <- buildToMemory root
  output2 <- buildToMemory root
  if output1 == output2
    then pure (Right ())
    else pure (Left (ReproError (diffOutputs output1 output2)))
```

### Step 2: Eliminate non-determinism sources

Audit code generation for non-deterministic output:

**File**: `packages/canopy-core/src/Generate/JavaScript/Expression.hs`

- Ensure Map iterations use `Map.toAscList` (deterministic) not `Map.toList` (also deterministic in Data.Map.Strict, but verify)
- Remove any timestamp injection in generated code
- Normalize file paths in generated source maps

### Step 3: Content-addressable output

Hash the generated JavaScript and include the hash in build output:

```
Build complete:
  Output: build/main.js (sha256:abc123...)
  Reproducible: yes
```

### Step 4: Lock file completeness check

Verify the lock file contains ALL transitive dependencies before building:

```haskell
verifyLockComplete :: LockFile -> Outline -> Either LockError ()
verifyLockComplete lf outline =
  let required = allTransitiveDeps outline
      locked = Map.keysSet (_lockPackages lf)
      missing = Set.difference required locked
  in if Set.null missing
     then Right ()
     else Left (MissingPackages missing)
```

### Step 5: CI integration

Add a CI step that builds the same project twice on different runners and verifies byte-identical output.

### Step 6: Tests

- Test that two builds of the same source produce identical output
- Test that lock file hash matches generated output
- Test deterministic Map iteration in codegen

## Dependencies
- Plan 14 (newtypes) for ContentHash type
