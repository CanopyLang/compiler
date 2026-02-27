# Plan 10 — Fix FFI Path Traversal Vulnerability

**Priority:** Tier 1 (Critical Architecture)
**Effort:** 4 hours
**Risk:** Low (adding validation, not changing behavior for valid paths)
**Files:** `packages/canopy-core/src/Foreign/FFI.hs`, `packages/canopy-core/src/Canonicalize/Module.hs`

---

## Problem

`FFITarget` contains `JavaScriptFFI !FilePath` where `FilePath` is unvalidated. The downstream loader in `Canonicalize/Module.hs` reads `rootDir </> jsPath` without sanitizing `jsPath`. A malicious or accidental `foreign import javascript "../../etc/passwd" as X` declaration would attempt to read an arbitrary file.

The CLAUDE.md security section requires validation of all file paths. `File/Archive.hs` already implements path traversal rejection for archive extraction, but the FFI path is not checked.

## Implementation

### Step 1: Create a path validation function

Add to `Foreign/FFI.hs` (or a shared `File/Validation.hs`):

```haskell
-- | Validate an FFI source file path.
--
-- Rejects paths that:
-- - Are absolute
-- - Contain path traversal components (..)
-- - Contain null bytes
-- - Do not end in .js
-- - Escape the project root
--
-- @since 0.19.2
validateFFIPath :: FilePath -> Either FFIError FilePath
validateFFIPath path
  | FP.isAbsolute path =
      Left (FFIPathError "FFI source path must be relative" path)
  | ".." `elem` FP.splitDirectories path =
      Left (FFIPathError "FFI source path cannot contain '..'" path)
  | '\0' `elem` path =
      Left (FFIPathError "FFI source path contains null byte" path)
  | not (FP.takeExtension path `elem` [".js", ".mjs"]) =
      Left (FFIPathError "FFI source path must end in .js or .mjs" path)
  | otherwise = Right (FP.normalise path)
```

### Step 2: Add FFIPathError to the error type

In `Foreign/FFI.hs`, add:

```haskell
data FFIError
  = ...
  | FFIPathError !Text !FilePath
  deriving (Show)
```

### Step 3: Validate at parse time

In `Canonicalize/Module.hs`, where `loadFFIContent` processes foreign imports, validate each path before reading:

```haskell
loadFFIContent :: [Src.ForeignImport] -> IO (Map String String)
loadFFIContent imports = do
  results <- traverse loadOne imports
  pure (Map.fromList (catMaybes results))
  where
    loadOne (Src.ForeignImport _ path _ _) =
      case FFI.validateFFIPath path of
        Left err -> -- report error, don't read file
        Right validPath -> -- proceed with reading
```

### Step 4: Validate at file read time (defense in depth)

Even after parse-time validation, add a runtime check in the file reader:

```haskell
readFFIFile :: FilePath -> FilePath -> IO (Either FFIError String)
readFFIFile rootDir jsPath = do
  let fullPath = rootDir </> jsPath
  canonicalRoot <- Dir.canonicalizePath rootDir
  canonicalFull <- Dir.canonicalizePath fullPath
  if canonicalRoot `isPrefixOf` canonicalFull
    then readFileContents fullPath
    else pure (Left (FFIPathError "FFI path escapes project root" jsPath))
```

This is the canonical defense against symlink-based traversal attacks — resolve both paths and verify containment.

### Step 5: Add a user-friendly error message

In `Reporting/Error/Syntax.hs` (or the appropriate sub-module after Plan 07):

```haskell
renderFFIPathError :: FFIError -> Doc
renderFFIPathError (FFIPathError reason path) =
  Doc.vcat
    [ Doc.text "-- FFI PATH ERROR"
    , Doc.empty
    , Doc.text "The foreign import path is not allowed:"
    , Doc.indent 4 (Doc.text path)
    , Doc.empty
    , Doc.text reason
    , Doc.empty
    , Doc.text "FFI source paths must be relative paths within your project"
    , Doc.text "directory, ending in .js or .mjs, without '..' components."
    ]
```

## Validation

```bash
make build && make test
```

Additionally, create a test case with a path traversal attempt and verify it produces the error:

```bash
# In a test project:
echo 'foreign import javascript "../../etc/passwd" as Evil' > test.can
canopy make test.can
# Should show FFI PATH ERROR, not attempt to read /etc/passwd
```

## Acceptance Criteria

- `foreign import javascript "../../anything"` produces a clear error, not a file read attempt
- Absolute paths like `foreign import javascript "/etc/passwd"` produce an error
- Null bytes in paths produce an error
- Non-.js extensions produce an error
- Symlink-based escapes are caught by `canonicalizePath` containment check
- All 2,376 tests pass
- New test cases added for each rejection condition
