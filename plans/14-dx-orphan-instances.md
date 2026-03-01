# Plan 14: Data-Destroying Orphan Instance Fix

**Priority:** HIGH
**Effort:** Small (≤8 hours)
**Risk:** Medium — affects canopy.json serialization

## Problem

`Canopy/Outline.hs` defines orphan ToJSON/FromJSON instances that destroy data:

```haskell
instance Json.ToJSON Constraint.Constraint where
  toJSON _ = Json.String "any"           -- ALL constraints become "any"

instance Json.ToJSON Licenses.License where
  toJSON _ = Json.String "BSD-3-Clause"  -- ALL licenses become BSD-3-Clause

instance Json.FromJSON Constraint.Constraint where
  parseJSON = ... <|> pure Constraint.anything  -- Range constraints become "anything"
```

A round-trip (read → modify → write) of `canopy.json` silently destroys all version constraints and license information.

## Files to Modify

### Option A: Fix the Instances (Preferred)

**`packages/canopy-core/src/Canopy/Outline.hs`**

Replace the data-destroying implementations with correct ones:

1. **`ToJSON Constraint`**: Serialize using the constraint's textual representation. Read `Canopy/Constraint.hs` to find the rendering function (likely `toChars` or similar). The output should be like `"1.0.0 <= v < 2.0.0"`.

2. **`FromJSON Constraint`**: Parse the full constraint syntax including range operators (`<=`, `<`). Don't fall back to `Constraint.anything` on parse failure — return a parse error.

3. **`ToJSON License`**: Serialize the actual SPDX identifier. Read `Canopy/Licenses.hs` to find the correct rendering function.

4. **`FromJSON License`**: Parse the SPDX identifier string. Don't accept arbitrary strings.

### Option B: Move Instances to Source Modules

Move the instances out of `Outline.hs` into the modules that define the types (`Canopy/Constraint.hs` and `Canopy/Licenses.hs`). This eliminates the orphan instances and puts the serialization logic next to the type definition.

### Either Option: Remove the Pragma

Remove `{-# OPTIONS_GHC -Wno-orphans #-}` from line 2 of `Outline.hs` after fixing.

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Add round-trip test: read a `canopy.json` with range constraints, write it back, verify constraints are preserved
4. Add round-trip test: same for licenses
5. Verify `canopy bump` and `canopy publish` correctly serialize constraints
