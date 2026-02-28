# Plan 29: Documentation Generation

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Low — new feature, no existing code changes

## Problem

There's no `canopy docs` command to generate documentation from source code. Users have to read source files directly or rely on external tools.

## Implementation Plan

### Step 1: Create docs command

**File**: `packages/canopy-terminal/src/Docs.hs` (NEW)

```haskell
module Docs (run, Flags(..)) where

data Flags = Flags
  { _docsOutput :: !OutputFormat
  , _docsDir :: !FilePath
  }

data OutputFormat = HTML | JSON | Markdown

run :: () -> Flags -> IO ()
```

### Step 2: Extract documentation from modules

Parse doc comments from Canopy source files:

```elm
{-| This module provides utility functions for working with lists.

# Transforming Lists
@docs map, filter, foldl

# Combining Lists
@docs append, concat
-}
module List exposing (..)

{-| Apply a function to every element of a list.

    List.map negate [1, 2, 3] == [-1, -2, -3]
-}
map : (a -> b) -> List a -> List b
```

### Step 3: Generate HTML output

Create a documentation site generator that produces:
- Module index page
- Per-module documentation pages
- Type signature display with syntax highlighting
- Example rendering
- Cross-linking between modules

### Step 4: Generate JSON output

Produce machine-readable JSON documentation for tooling integration (editor hovers, autocomplete descriptions).

### Step 5: Integrate with build

- `canopy docs` — generate docs for current project
- `canopy docs --output=json` — JSON format
- `canopy docs --serve` — start local server for browsing

### Step 6: Register command

**File**: `packages/canopy-terminal/src/CLI/Commands.hs`

Register the `docs` command following existing patterns.

### Step 7: Tests

- Test doc comment extraction
- Test HTML generation
- Test JSON format
- Golden tests for generated documentation

## Dependencies
- None
