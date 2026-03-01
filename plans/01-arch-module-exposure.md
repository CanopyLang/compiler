# Plan 01: Public/Internal Module Split

**Priority**: CRITICAL
**Effort**: Medium (2-3 days)
**Risk**: Low
**Audit Finding**: 206 modules exposed from canopy-core; ~88% are internal implementation details

---

## Problem

Every module in canopy-core is publicly exposed in the cabal file. This means canopy-terminal, canopy-builder, canopy-driver, and any future downstream consumer can import internal implementation details like `Type.Solve.Pool`, `Canonicalize.Environment.Dups`, or `Parse.Primitives`.

**Consequences:**
- Any refactoring of canopy-core internals is a breaking change
- No enforcement of architectural boundaries
- Internal modules accumulate implicit downstream dependents
- The codebase will calcify within 2 years as internal APIs become load-bearing

---

## Solution

Split canopy-core's exposed-modules into a curated public API (~30 modules) and move everything else to other-modules (internal).

---

## Implementation

### Step 1: Define the Public API Surface

These modules form the genuine public API:

**AST Types (6 modules):**
- `AST.Source`
- `AST.Canonical`
- `AST.Canonical.Types`
- `AST.Optimized`
- `AST.Optimized.Expr`
- `AST.Optimized.Graph`

**Core Data Types (10 modules):**
- `Canopy.Data.Name`
- `Canopy.Data.Utf8`
- `Canopy.Data.Index`
- `Canopy.Data.NonEmptyList`
- `Canopy.Data.OneOrMore`
- `Canopy.ModuleName`
- `Canopy.Package`
- `Canopy.Version`
- `Canopy.Float`
- `Canopy.Constraint`

**Compiler Interface (4 modules):**
- `Canopy.Compiler.Imports`
- `Canopy.Compiler.Type`
- `Canopy.Compiler.Type.Extract`
- `Canopy.Interface`

**Public Operations (8 modules):**
- `Format` — code formatter
- `Canopy.Outline` — project configuration
- `Canopy.Docs` — documentation generation
- `File.FileSystem` — safe file operations
- `FFI.Types` — FFI type definitions
- `FFI.Capability` — capability types
- `Reporting.Diagnostic` — structured diagnostics
- `Reporting.Report` — error/warning report types

**Code Generation (3 modules):**
- `Generate.JavaScript` — JS generation entry point
- `Generate.JavaScript.SourceMap` — source map generation
- `Generate.Html` — HTML generation

### Step 2: Audit Downstream Imports

For each package that depends on canopy-core, grep all imports and categorize:

```bash
# For canopy-terminal
grep -rn "^import" packages/canopy-terminal/src/ --include="*.hs" | \
  grep -v "canopy-terminal" | sort -u

# For canopy-builder
grep -rn "^import" packages/canopy-builder/src/ --include="*.hs" | \
  grep -v "canopy-builder" | sort -u

# For canopy-driver
grep -rn "^import" packages/canopy-driver/src/ --include="*.hs" | \
  grep -v "canopy-driver" | sort -u
```

For each internal module import found:
1. If the consumer only needs types → re-export from a public module
2. If the consumer needs internal functions → create a new public API function that wraps the internal
3. If the import is genuinely needed (e.g., canopy-builder needs Parse.Module internals) → document the exception

### Step 3: Update canopy-core.cabal

```cabal
library
  exposed-modules:
    -- AST Types
    AST.Source
    AST.Canonical
    AST.Canonical.Types
    AST.Optimized
    AST.Optimized.Expr
    AST.Optimized.Graph
    -- Core Data Types
    Canopy.Data.Name
    Canopy.Data.Utf8
    ...
    -- (31 total modules)

  other-modules:
    -- Parser internals
    Parse.Primitives
    Parse.Expression
    Parse.Pattern
    ...
    -- Type system internals
    Type.Constrain.Expression
    Type.Solve.Pool
    Type.Unify
    ...
    -- (175 internal modules)
```

### Step 4: Create Re-Export Modules Where Needed

If canopy-terminal currently imports `Type.Error` directly, and that needs to stay accessible, add it to the public API or create a re-export:

```haskell
-- In a public module like Canopy.Compiler.Type:
module Canopy.Compiler.Type
  ( -- existing exports
  , module Type.Error  -- re-export error types
  ) where
```

### Step 5: Build and Fix

```bash
make build  # Will fail with "module not in scope" errors for hidden modules
```

Each error reveals a place where a downstream package reaches into internals. Fix each one by:
1. Adding a public re-export
2. Creating a proper API wrapper
3. Moving the function to a public module

---

## Validation

```bash
# Build all packages
make build

# Verify module count
grep "exposed-modules:" packages/canopy-core/canopy-core.cabal -A1000 | \
  grep "^    " | wc -l  # Should be ~31

# Verify no internal module imports from downstream
grep -rn "^import.*qualified.*Parse\." packages/canopy-terminal/src/ | \
  grep -v "Parse.Module"  # Should be empty

# All tests pass
make test
```

---

## Success Criteria

- [ ] canopy-core exposes <= 35 modules
- [ ] canopy-core has >= 170 modules in other-modules
- [ ] All downstream packages build without modification to their imports OR with documented re-exports
- [ ] `make build` passes with zero warnings
- [ ] `make test` passes (3350+ tests)
- [ ] No downstream package imports a module from other-modules
