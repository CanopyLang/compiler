# Plan 22: Path Traversal Hardening

**Priority:** MEDIUM
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

`File/Archive.hs:198` uses `List.isInfixOf "../"` for path traversal detection, which only checks forward-slash separators. On Windows, `"..\\"` bypasses this check. The correct approach already exists in `Canopy/PathValidation.hs:65` using `".." elem FP.splitDirectories path` (platform-independent), but Archive.hs doesn't use it.

Same issue in `File/Package.hs:213`.

## Files to Modify

### `packages/canopy-core/src/File/Archive.hs`

**Current (line 198):**
```haskell
not (List.isInfixOf "../" path) &&
```

**Replace with:**
```haskell
not (".." `elem` FP.splitDirectories path) &&
```

Or better, import and use the existing `PathValidation.validatePath`:
```haskell
import qualified Canopy.PathValidation as PathValidation

isAllowedPath :: FilePath -> Bool
isAllowedPath path =
  case PathValidation.validatePath path of
    Left _ -> False
    Right validPath -> isAllowedPrefix validPath
  where
    isAllowedPrefix p =
      List.isPrefixOf "src/" p
        || p == "LICENSE"
        || p == "README.md"
        || p == "canopy.json"
        || p == "elm.json"
```

### `packages/canopy-core/src/File/Package.hs`

**Line 213:** Same fix — replace `List.isInfixOf "../"` with `".." elem FP.splitDirectories`.

### Additional Hardening

After extraction, verify the resolved path is within the destination directory:
```haskell
let resolvedDest = FP.normalise (destination </> relativePath)
    normalDest = FP.normalise destination
in unless (normalDest `List.isPrefixOf` resolvedDest)
     (throwIO (PathTraversalDetected relativePath))
```

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Add test: archive entry with `..\\` (Windows separator) is rejected
4. Add test: archive entry with `../` is rejected
5. Add test: archive entry with `src/../../etc/passwd` is rejected
6. Add test: normal `src/Module.can` is accepted
