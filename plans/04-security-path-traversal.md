# Plan 04: File URL Path Traversal Prevention

## Priority: HIGH
## Effort: Small (2-4 hours)
## Risk: Low — applying existing pattern from FFI validator

## Problem

`Http.hs` contains `fileUrlToPath` that extracts filesystem paths from `file://` URLs using `URI.parseURI`. While it uses a proper URI parser (not raw string manipulation), it does NOT validate the extracted path for filesystem-level attacks — no `.."` traversal check, no absolute path rejection, no null byte check. An attacker could craft a package reference pointing to `file:///etc/passwd` or `file://foo/../../../sensitive-data`.

Meanwhile, `FFI/Validator.hs` already has a proper `validateFFIPath` that rejects traversal — but it's only applied to FFI paths, not to HTTP file URLs.

### Current Code

**Missing filesystem validation** (packages/canopy-builder/src/Http.hs, lines 155-159):
```haskell
fileUrlToPath :: String -> Maybe FilePath
fileUrlToPath url =
  case URI.parseURI url of
    Just uri | URI.uriScheme uri == "file:" -> Just (URI.uriPath uri)
    _ -> Nothing
```

The URI parser validates URL syntax but `URI.uriPath` can still return absolute paths, paths with `..`, etc.

**Correct reference** (packages/canopy-core/src/Canonicalize/Module/FFI.hs, lines 86-100):
```haskell
validateFFIPath :: FilePath -> Either String FilePath
validateFFIPath path
  | FP.isAbsolute path = Left "FFI source path must be relative"
  | ".." `elem` FP.splitDirectories path = Left "FFI source path cannot contain '..'"
  | '\0' `elem` path = Left "FFI source path contains null byte"
  | not (FP.takeExtension path `elem` [".js", ".mjs"]) = Left "FFI source path must end in .js or .mjs"
  | otherwise = Right (FP.normalise path)
```

## Implementation Plan

### Step 1: Create shared path validation module

**File**: `packages/canopy-builder/src/Canopy/PathValidation.hs` (NEW)

Extract the filesystem safety checks from FFI.hs into a shared module:

```haskell
module Canopy.PathValidation
  ( validatePath
  , PathError(..)
  ) where

data PathError
  = PathAbsolute !FilePath
  | PathTraversal !FilePath
  | PathNullByte !FilePath
  deriving (Show)

validatePath :: FilePath -> Either PathError FilePath
validatePath path
  | FP.isAbsolute path = Left (PathAbsolute path)
  | ".." `elem` FP.splitDirectories path = Left (PathTraversal path)
  | '\0' `elem` path = Left (PathNullByte path)
  | otherwise = Right (FP.normalise path)
```

### Step 2: Add validation after URI parsing

**File**: `packages/canopy-builder/src/Http.hs`

```haskell
fileUrlToPath :: String -> Maybe FilePath
fileUrlToPath url =
  case URI.parseURI url of
    Just uri | URI.uriScheme uri == "file:" ->
      either (const Nothing) Just (PathValidation.validatePath (URI.uriPath uri))
    _ -> Nothing
```

### Step 3: Update FFI.hs to use shared module

**File**: `packages/canopy-core/src/Canonicalize/Module/FFI.hs`

Replace inline validation with call to shared `PathValidation.validatePath`, keeping the additional `.js`/`.mjs` extension check as FFI-specific.

### Step 4: Tests

- Test rejection of `file:///etc/passwd` (absolute path)
- Test rejection of `file://foo/../../../secret` (traversal)
- Test rejection of paths with null bytes
- Test acceptance of valid relative `file://` URLs
- Test normalization of `./some/./path`

## Dependencies
- None
