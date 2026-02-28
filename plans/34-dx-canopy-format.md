# Plan 34: Code Formatter (`canopy format`)

## Priority: MEDIUM
## Effort: Large (5-10 days)
## Risk: Medium — opinionated formatting decisions

## Problem

There's a `Format.hs` module in canopy-core but no `canopy format` CLI command. Users can't auto-format their Canopy source files.

### Key Files
- `packages/canopy-core/src/Format.hs` — existing formatter logic

## Implementation Plan

### Step 1: Audit existing Format.hs

Read the current `Format.hs` to understand what's implemented:
- Does it handle all AST nodes?
- What formatting decisions does it make?
- Is it round-trip safe (format(format(x)) == format(x))?

### Step 2: Create format command

**File**: `packages/canopy-terminal/src/Format.hs` (NEW — CLI wrapper)

```haskell
module Format.Command (run, Flags(..)) where

data Flags = Flags
  { _formatCheck :: !Bool     -- Check only, don't modify
  , _formatStdin :: !Bool     -- Read from stdin
  , _formatWidth :: !Int      -- Line width (default: 80)
  }

run :: [FilePath] -> Flags -> IO ()
run paths flags
  | _formatCheck flags = checkFormatting paths
  | otherwise = formatFiles paths
```

### Step 3: Implement idempotent formatting

Ensure formatting is idempotent: applying the formatter twice produces the same result as applying it once. Test with property:

```haskell
prop_idempotent :: Source -> Bool
prop_idempotent src =
  format (format src) == format src
```

### Step 4: Preserve comments and whitespace semantics

The formatter must preserve:
- Doc comments (`{-| ... -}`)
- Line comments (`-- ...`)
- Significant whitespace (indentation-based syntax)

### Step 5: CLI integration

- `canopy format src/` — format all .can files in directory
- `canopy format --check src/` — check formatting without changing
- `canopy format --stdin` — format from stdin (for editor integration)
- Exit code 1 when `--check` finds unformatted files

### Step 6: Editor integration

Document how to configure VS Code, Vim, and Emacs to run `canopy format --stdin` on save.

### Step 7: Tests

- Golden tests for formatted output
- Idempotency property test
- Comment preservation test
- Round-trip test (parse → format → parse produces same AST)

## Dependencies
- None
