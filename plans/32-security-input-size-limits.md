# Plan 32: Input Size Limits

## Priority: HIGH
## Effort: Small (4-8 hours)
## Risk: Low — defensive limits at system boundaries

## Problem

The compiler has no limits on input sizes. A malicious or accidentally-huge source file can consume unbounded memory and CPU. The CLAUDE.md mentions input validation but it's not implemented at system boundaries.

## Implementation Plan

### Step 1: Define limits

**File**: `packages/canopy-core/src/Canopy/Limits.hs` (NEW)

```haskell
module Canopy.Limits where

-- | Maximum source file size (10 MB)
maxSourceFileSize :: Int
maxSourceFileSize = 10 * 1024 * 1024

-- | Maximum number of modules in a project
maxModuleCount :: Int
maxModuleCount = 10000

-- | Maximum import count per module
maxImportsPerModule :: Int
maxImportsPerModule = 500

-- | Maximum canopy.json size (1 MB)
maxOutlineSize :: Int
maxOutlineSize = 1024 * 1024

-- | Maximum dependency count
maxDependencies :: Int
maxDependencies = 200

-- | Maximum lock file size (10 MB)
maxLockFileSize :: Int
maxLockFileSize = 10 * 1024 * 1024
```

### Step 2: Apply limits at file read boundaries

**File**: `packages/canopy-builder/src/Compiler.hs`

Before parsing any source file:
```haskell
readSourceFile :: FilePath -> IO (Either CompileError ByteString)
readSourceFile path = do
  size <- Dir.getFileSize path
  if size > fromIntegral Limits.maxSourceFileSize
    then pure (Left (FileTooLarge path size Limits.maxSourceFileSize))
    else Right <$> BS.readFile path
```

### Step 3: Apply limits to outline parsing

**File**: `packages/canopy-core/src/Canopy/Outline.hs`

Check canopy.json size before parsing. Check dependency count after parsing.

### Step 4: Apply limits to lock file reading

**File**: `packages/canopy-builder/src/Builder/LockFile.hs`

Check lock file size before parsing.

### Step 5: Clear error messages

```
-- FILE TOO LARGE -------- src/HugeModule.can

This source file is 15 MB, which exceeds the 10 MB limit.

Consider splitting it into smaller modules.
```

### Step 6: Tests

- Test rejection of oversized source files
- Test rejection of oversized canopy.json
- Test acceptance at exactly the limit
- Test error message format

## Dependencies
- None
