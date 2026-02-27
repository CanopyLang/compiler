# Plan 28 — Move Data.* Modules to Canopy.Data.*

**Priority:** Tier 5 (Hardening)
**Effort:** 2 days
**Risk:** Medium (many import changes)
**Files:** ~80 files across all packages

---

## Problem

13 internal modules occupy `Data.*` hierarchy normally reserved for Hackage/standard library:

- `Data.Bag`
- `Data.Index`
- `Data.Map.Utils`
- `Data.Name` (+ 5 sub-modules: Constants, Core, Generation, Kernel, TypeVariable)
- `Data.NonEmptyList`
- `Data.OneOrMore`
- `Data.Utf8` (+ 7 sub-modules: Binary, Builder, Core, Creation, Encoding, Manipulation, Types)

From an import statement, it is impossible to tell whether `Data.Name` or `Data.Bag` is a Hackage package or internal code. This causes confusion for contributors and makes dependency auditing harder.

## Target Namespace

```
Data.Bag           → Canopy.Data.Bag
Data.Index         → Canopy.Data.Index
Data.Map.Utils     → Canopy.Data.Map.Utils
Data.Name          → Canopy.Data.Name
Data.Name.*        → Canopy.Data.Name.*
Data.NonEmptyList  → Canopy.Data.NonEmptyList
Data.OneOrMore     → Canopy.Data.OneOrMore
Data.Utf8          → Canopy.Data.Utf8
Data.Utf8.*        → Canopy.Data.Utf8.*
```

## Implementation

### Step 1: Move files

```bash
mkdir -p packages/canopy-core/src/Canopy/Data/Name
mkdir -p packages/canopy-core/src/Canopy/Data/Map
mkdir -p packages/canopy-core/src/Canopy/Data/Utf8

mv packages/canopy-core/src/Data/Bag.hs packages/canopy-core/src/Canopy/Data/Bag.hs
mv packages/canopy-core/src/Data/Index.hs packages/canopy-core/src/Canopy/Data/Index.hs
# ... etc for all files
```

### Step 2: Update module declarations

In each moved file, update the `module` declaration:

```haskell
-- Before:
module Data.Bag (...) where
-- After:
module Canopy.Data.Bag (...) where
```

### Step 3: Update all imports

For each moved module, find and replace all import statements across the entire codebase:

```bash
# Example for Data.Bag:
grep -rn "import.*Data\.Bag" packages/*/src/ test/ | wc -l
# Then replace in each file:
# "import qualified Data.Bag" → "import qualified Canopy.Data.Bag"
# "import Data.Bag" → "import Canopy.Data.Bag"
```

### Step 4: Update canopy-core.cabal

Update the exposed-modules list with new module names and remove old ones.

### Step 5: Keep backward-compatibility re-exports (optional, temporary)

For a transition period, keep thin re-export modules at the old locations:

```haskell
-- Data/Bag.hs (re-export only, marked deprecated)
module Data.Bag {-# DEPRECATED "Use Canopy.Data.Bag" #-} (module Canopy.Data.Bag) where
import Canopy.Data.Bag
```

Remove these after all packages have been updated.

### Step 6: Build and fix

```bash
make build 2>&1 | head -100
# Fix any remaining import references
make build && make test
```

## Validation

```bash
make build && make test

# Verify no old-namespace modules remain:
grep -rn "import.*Data\.Bag\|import.*Data\.Index\|import.*Data\.Name\b\|import.*Data\.NonEmptyList\|import.*Data\.OneOrMore\|import.*Data\.Utf8" packages/*/src/ | grep -v "Canopy.Data"
# Should return 0 results (or only re-export modules if kept)
```

## Acceptance Criteria

- All 13 internal `Data.*` modules moved to `Canopy.Data.*`
- All imports updated across all packages
- `make build && make test` passes
- No confusion between internal and Hackage `Data.*` modules
