# Plan 07 — Split Reporting/Error/Syntax.hs

**Priority:** Tier 1 (Critical Architecture)
**Effort:** 2 days
**Risk:** Medium (many importers need updating)
**Files:** ~12 files created/modified

---

## Problem

`Reporting/Error/Syntax.hs` is **6,768 lines** — 8% of the entire source codebase in one file. It contains 80+ error constructors covering every syntax variant (expressions, patterns, types, declarations, modules, imports, effects, ports, FFI). This is unmaintainable: every new syntax feature requires editing a 6,768-line file, and the lack of separation makes it impossible to understand which errors belong to which compiler phase.

## Architecture

### Current Structure

```
Reporting/Error/Syntax.hs  (6,768 lines, 80+ constructors, 1 file)
```

### Target Structure

```
Reporting/Error/Syntax.hs             (~200 lines — re-exports + top-level dispatch)
Reporting/Error/Syntax/Expression.hs  (~800 lines — expression parse errors)
Reporting/Error/Syntax/Pattern.hs     (~500 lines — pattern parse errors)
Reporting/Error/Syntax/Type.hs        (~500 lines — type parse errors)
Reporting/Error/Syntax/Declaration.hs (~600 lines — declaration errors)
Reporting/Error/Syntax/Module.hs      (~500 lines — module/import/export errors)
Reporting/Error/Syntax/Literal.hs     (~400 lines — string/number/char errors)
Reporting/Error/Syntax/Effects.hs     (~400 lines — port/effect/FFI errors)
Reporting/Error/Syntax/Common.hs      (~300 lines — shared types, Region helpers)
```

## Implementation

### Step 1: Analyze the error constructors

Read `Syntax.hs` and categorize every error type and its rendering function by domain:

```bash
grep "^data\|^  |" packages/canopy-core/src/Reporting/Error/Syntax.hs | head -200
```

Map each constructor to its target sub-module based on what it describes.

### Step 2: Create Syntax/Common.hs

Extract shared types used across multiple sub-modules:
- `Region` re-exports
- `Row`/`Col` type aliases
- Helper functions (`toReport`, `toSnippet`, common rendering utilities)
- `SyntaxError` top-level sum type that delegates to sub-module error types

```haskell
module Reporting.Error.Syntax.Common
  ( SyntaxError(..)
  , toReport
  , toSnippet
  -- ... shared utilities
  ) where
```

### Step 3: Create each sub-module

For each sub-module, move the relevant:
1. Error data types (e.g., `ExprError`, `PatternError`)
2. Their `toReport`/`toDiagnostic` rendering functions
3. Their hint generation functions
4. Any helper functions used only by that sub-module

Each sub-module should:
- Import `Reporting.Error.Syntax.Common` for shared utilities
- Export its error type and rendering function
- Be self-contained (no cross-references between sub-modules)

### Step 4: Make Syntax.hs a thin re-export module

```haskell
-- | Syntax error types and rendering.
--
-- This module re-exports all syntax error sub-modules for backward compatibility.
-- New code should import the specific sub-module it needs.
module Reporting.Error.Syntax
  ( module Reporting.Error.Syntax.Common
  , module Reporting.Error.Syntax.Expression
  , module Reporting.Error.Syntax.Pattern
  , module Reporting.Error.Syntax.Type
  , module Reporting.Error.Syntax.Declaration
  , module Reporting.Error.Syntax.Module
  , module Reporting.Error.Syntax.Literal
  , module Reporting.Error.Syntax.Effects
  ) where

import Reporting.Error.Syntax.Common
import Reporting.Error.Syntax.Expression
import Reporting.Error.Syntax.Pattern
import Reporting.Error.Syntax.Type
import Reporting.Error.Syntax.Declaration
import Reporting.Error.Syntax.Module
import Reporting.Error.Syntax.Literal
import Reporting.Error.Syntax.Effects
```

### Step 5: Update canopy-core.cabal

Add all new sub-modules to the exposed-modules list:

```yaml
exposed-modules:
  ...
  Reporting.Error.Syntax
  Reporting.Error.Syntax.Common
  Reporting.Error.Syntax.Expression
  Reporting.Error.Syntax.Pattern
  Reporting.Error.Syntax.Type
  Reporting.Error.Syntax.Declaration
  Reporting.Error.Syntax.Module
  Reporting.Error.Syntax.Literal
  Reporting.Error.Syntax.Effects
```

### Step 6: Update all importers

Since `Syntax.hs` re-exports everything, existing `import qualified Reporting.Error.Syntax as E` imports will continue to work. However, for long-term maintenance, update direct importers to use the specific sub-module they need:

```bash
grep -rn "Reporting.Error.Syntax" packages/canopy-core/src/ | grep -v "Syntax/" | grep import
```

### Step 7: Verify no sub-module exceeds 1,000 lines

```bash
wc -l packages/canopy-core/src/Reporting/Error/Syntax/*.hs
```

If any sub-module exceeds 1,000 lines, split it further.

## Validation

```bash
make build && make test
```

All 2,376 tests must pass. The re-export module ensures backward compatibility.

## Acceptance Criteria

- `Reporting/Error/Syntax.hs` is ≤200 lines (re-exports only)
- Each sub-module is ≤1,000 lines
- No sub-module imports another sub-module (except Common)
- All existing imports continue to work via re-exports
- `make build && make test` passes
- Total line count across all sub-modules equals original 6,768 ± 50 lines (accounting for new module headers)
