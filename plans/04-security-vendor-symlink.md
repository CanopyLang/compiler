# Plan 04: Vendor Symlink Safety

- **Priority**: HIGH
- **Effort**: Small (3-4h)
- **Risk**: Low

## Problem

The `canopy vendor` command recursively copies package directories from the
global cache to the project's `vendor/` directory. The copy logic uses
`Dir.doesDirectoryExist` to distinguish files from directories, and
`Dir.copyFile` to copy files. Neither checks for symbolic links.

If a malicious package places a symlink inside its cached directory (e.g.,
`src/evil -> /etc/passwd`), the vendor command would follow the symlink and
copy the target file into the vendor directory. More dangerously, if a directory
symlink points outside the package (e.g., `src -> /home/user/.ssh`), the entire
target tree would be recursively copied.

The archive extraction code in `File.Archive` also does not check for symlinks
in ZIP entries, though ZIP symlink handling is less common on the extraction side.

### Current Code

**File**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Vendor.hs`

At lines 168-182, `copyPackageDir` and `copyEntry` recursively copy without
symlink checks:

```haskell
copyPackageDir :: FilePath -> FilePath -> IO ()
copyPackageDir src dst = do
  Dir.createDirectoryIfMissing True dst
  contents <- Dir.listDirectory src
  mapM_ (copyEntry src dst) contents

copyEntry :: FilePath -> FilePath -> FilePath -> IO ()
copyEntry srcBase destBase name = do
  let srcPath = srcBase </> name
      destPath = destBase </> name
  isDir <- Dir.doesDirectoryExist srcPath
  if isDir
    then copyPackageDir srcPath destPath
    else Dir.copyFile srcPath destPath
```

Key issues:
1. `Dir.doesDirectoryExist` returns `True` for directory symlinks, causing
   the code to follow them recursively.
2. `Dir.copyFile` follows file symlinks and copies the target content.
3. No check that `srcPath` is still within the expected package directory
   (symlinks could escape).

**File**: `/home/quinten/fh/canopy/packages/canopy-core/src/File/Archive.hs`

The `isAllowedPath` function (line 194) checks for path traversal (`..`) and
null characters, but does not handle ZIP entries that represent symbolic links.
The `Codec.Archive.Zip` library does support symlink entries, though they are
uncommon in package archives.

A grep for `isSymbolicLink` or `pathIsSymbolicLink` across the codebase
returns zero results, confirming that symlink checking is completely absent.

## Files to Modify

### 1. `Vendor.hs` -- `copyEntry` (lines 175-182)

**Change**: Before copying, check if the source path is a symbolic link.
Skip symlinks with a warning.

**Current**:
```haskell
copyEntry :: FilePath -> FilePath -> FilePath -> IO ()
copyEntry srcBase destBase name = do
  let srcPath = srcBase </> name
      destPath = destBase </> name
  isDir <- Dir.doesDirectoryExist srcPath
  if isDir
    then copyPackageDir srcPath destPath
    else Dir.copyFile srcPath destPath
```

**Proposed**:
```haskell
copyEntry :: FilePath -> FilePath -> FilePath -> IO ()
copyEntry srcBase destBase name = do
  let srcPath = srcBase </> name
      destPath = destBase </> name
  isLink <- Dir.pathIsSymbolicLink srcPath
  if isLink
    then Log.logEvent (SecurityEvent "vendor-skip-symlink" (Text.pack srcPath))
    else do
      isDir <- Dir.doesDirectoryExist srcPath
      if isDir
        then copyPackageDir srcPath destPath
        else Dir.copyFile srcPath destPath
```

Note: `Dir.pathIsSymbolicLink` is available from `directory >= 1.3.0.0` (ships
with GHC 8.6+). It returns `True` for symlinks without following them.

**Add import**:
```haskell
import qualified Logging.Logger as Log
import Logging.Event (LogEvent (..))
import qualified Data.Text as Text
```

Also add the `SecurityEvent` constructor to `Logging.Event` if it does not exist.
If adding a new constructor is too invasive, use the existing `PackageOperation`
constructor:

```haskell
Log.logEvent (PackageOperation "vendor-skip-symlink" (Text.pack srcPath))
```

### 2. `Vendor.hs` -- `copyPackageDir` (lines 168-172)

**Optional enhancement**: Also verify that the source directory itself is not
a symlink before recursing:

```haskell
copyPackageDir :: FilePath -> FilePath -> IO ()
copyPackageDir src dst = do
  isLink <- Dir.pathIsSymbolicLink src
  Monad.when (not isLink) $ do
    Dir.createDirectoryIfMissing True dst
    contents <- Dir.listDirectory src
    mapM_ (copyEntry src dst) contents
```

### 3. `File/Archive.hs` -- ZIP symlink entries

**Change**: In `isAllowedPath` (line 194), also reject entries whose external
file attributes indicate a symlink. The `Codec.Archive.Zip` library stores
Unix file mode in `eExternalFileAttributes`. Symlinks have the `0o120000` bit
set.

Add a helper:

```haskell
-- | Check whether a ZIP entry represents a symbolic link.
--
-- Unix symlinks have mode bits 0o120000 set in the external file attributes.
-- The external attributes are stored in the upper 16 bits of the 32-bit field
-- on Unix systems.
isSymlinkEntry :: Zip.Entry -> Bool
isSymlinkEntry entry =
  let attrs = Zip.eExternalFileAttributes entry
      unixMode = fromIntegral (attrs `shiftR` 16) :: Word32
  in unixMode .&. 0o170000 == 0o120000
```

Modify `writeEntry` (line 148) to skip symlink entries:

```haskell
writeEntry :: FilePath -> Int -> Zip.Entry -> IO ()
writeEntry destination rootDepth entry = do
  let relativePath = extractRelativePath rootDepth entry
      allowed = isAllowedPath relativePath
                && isWithinDestination destination relativePath
                && not (isSymlinkEntry entry)
  Monad.when allowed $ ...
```

Apply the same check in `writeEntryReturnCanopyJson` (line 276).

**Add imports**:
```haskell
import Data.Bits ((.&.), shiftR)
import Data.Word (Word32)
```

## Verification

### Unit Tests for Vendor

Add tests in `test/Unit/VendorTest.hs`:

1. **Test regular files are copied**: Create a temp directory with normal files,
   run `copyPackageDir`, verify files are in the destination.

2. **Test symlinks are skipped**: Create a temp directory with a symlink, run
   `copyPackageDir`, verify the symlink target is NOT in the destination.

3. **Test directory symlinks are skipped**: Create a directory symlink, verify
   the linked directory is not recursed into.

### Unit Tests for Archive

Add tests in `test/Unit/File/ArchiveTest.hs`:

1. **Test symlink ZIP entries are rejected**: Create a ZIP archive with a
   symlink entry (set external attributes to indicate symlink), verify
   `isSymlinkEntry` returns `True` and the entry is not extracted.

### Commands

```bash
# Build
stack build

# Run all tests
stack test

# Run vendor-specific tests
stack test --ta="--pattern Vendor"

# Run archive-specific tests
stack test --ta="--pattern Archive"

# Manual verification: create a symlink in a cached package and run canopy vendor
mkdir -p /tmp/test-vendor/src
ln -s /etc/passwd /tmp/test-vendor/src/evil
# Verify copyPackageDir skips the symlink
```
