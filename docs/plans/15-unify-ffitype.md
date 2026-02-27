# Plan 15 — Unify Duplicate FFIType Definitions

**Priority:** Tier 2 (Type Safety)
**Effort:** 4 hours
**Risk:** Low
**Files:** `packages/canopy-core/src/Foreign/FFI.hs`, `packages/canopy-core/src/FFI/Validator.hs`, `packages/canopy-core/src/Generate/JavaScript.hs`, ~1 more

---

## Problem

Two separate, incompatible `FFIType` definitions exist:

- `Foreign.FFI.FFIType` — used for parsing JSDoc and binding generation
- `FFI.Validator.FFIType` — used for runtime validator generation

These overlap in purpose but differ structurally. `Foreign.FFI.FFIType` has `FFIRecord` and `FFIOpaque !Text`; `FFI.Validator.FFIType` has `FFIOpaque !Text` but no `FFIRecord`. A bridge function `ffiTypeToValidator` manually converts between them.

Adding a new FFI type to one definition requires manually updating the other, with no compile-time guarantee of sync.

## Implementation

### Step 1: Define a single canonical FFIType

Choose which definition is more complete (likely `Foreign.FFI.FFIType`) and make it the single source of truth. Move it to a shared module:

```haskell
-- FFI/Types.hs (new module, or extend existing FFI/Capability.hs)
module FFI.Types
  ( FFIType(..)
  ) where

data FFIType
  = FFIBasic !BasicType
  | FFIResult !FFIType !FFIType
  | FFITask !FFIType !FFIType
  | FFIMaybe !FFIType
  | FFIList !FFIType
  | FFIFunctionType ![FFIType] !FFIType
  | FFIOpaque !Text
  | FFITuple ![FFIType]
  | FFIRecord ![(Text, FFIType)]
  deriving (Eq, Show)

data BasicType
  = FFIInt
  | FFIFloat
  | FFIString
  | FFIBool
  | FFIUnit
  deriving (Eq, Show)
```

### Step 2: Update Foreign.FFI to import from FFI.Types

```haskell
-- Foreign/FFI.hs
import FFI.Types (FFIType(..), BasicType(..))
-- Remove the local FFIType definition
```

### Step 3: Update FFI.Validator to import from FFI.Types

```haskell
-- FFI/Validator.hs
import FFI.Types (FFIType(..), BasicType(..))
-- Remove the local FFIType definition
```

### Step 4: Remove the bridge function

`ffiTypeToValidator` in `Generate/JavaScript.hs` converts between the two types. With a single definition, this function becomes unnecessary — delete it and use `FFIType` directly.

### Step 5: Handle structural differences

If `FFI.Validator.FFIType` lacks `FFIRecord`, add support for it in the validator generator. The validator for a record type should validate each field:

```haskell
generateRecordValidator :: [(Text, FFIType)] -> Builder
generateRecordValidator fields =
  -- Generate: function(v) { return typeof v === 'object' && v !== null
  --   && hasField("name", validateType, v) && ... }
```

### Step 6: Update canopy-core.cabal

Add `FFI.Types` to exposed-modules.

## Validation

```bash
make build && make test
```

## Acceptance Criteria

- Exactly one `FFIType` definition exists in the codebase
- No bridge/conversion functions between FFI types
- Both `Foreign.FFI` and `FFI.Validator` import from the same module
- `make build && make test` passes
