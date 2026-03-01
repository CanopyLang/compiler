# Plan 02: Zip Bomb Protection

- **Priority**: HIGH
- **Effort**: Small (4-6h)
- **Risk**: Low

## Problem

The archive extraction code in `File.Archive` extracts every entry from a ZIP
file without tracking total extracted bytes. A malicious package archive could
contain a zip bomb -- a small ZIP file that decompresses to gigabytes or
terabytes of data, causing disk exhaustion and/or out-of-memory conditions.

While `Canopy.Limits` defines size limits for source files, outlines, and lock
files, there is no limit on total archive extraction size.

### Current Code

**File**: `/home/quinten/fh/canopy/packages/canopy-core/src/File/Archive.hs`

The extraction loop at lines 92-99 iterates over all entries with no size check:

```haskell
writePackage :: FilePath -> Zip.Archive -> IO ()
writePackage destination archive =
  case Zip.zEntries archive of
    [] -> Monad.return ()
    allEntries@(firstEntry : _) -> do
      checkDestinationExists destination
      let rootDepth = calculateRootDepth firstEntry
      Foldable.traverse_ (writeEntry destination rootDepth) allEntries
```

Each entry is written at lines 260-270 without size tracking:

```haskell
writeEntryFile :: FilePath -> FilePath -> Zip.Entry -> IO ()
writeEntryFile destination relativePath entry = do
  let fullPath = destination </> relativePath
      fileContent = Zip.fromEntry entry
  Dir.createDirectoryIfMissing True (FP.takeDirectory fullPath)
  if isCriticalFile relativePath
    then Atomic.writeLazyBytesAtomic fullPath fileContent
    else LBS.writeFile fullPath fileContent
```

`Zip.fromEntry` returns a lazy `ByteString` of arbitrary size. There is no
check on `LBS.length fileContent` nor on cumulative bytes written.

Similarly, `writeEntryFileForJson` at lines 307-357 has no size tracking.

**File**: `/home/quinten/fh/canopy/packages/canopy-core/src/Canopy/Limits.hs`

The existing limits module already has the pattern we need:

```haskell
maxSourceFileBytes :: Int
maxSourceFileBytes = 10 * 1024 * 1024  -- 10 MB

checkFileSize :: FilePath -> Int -> Int -> Maybe FileSizeError
checkFileSize path actualSize limit
  | actualSize > limit = Just (FileSizeError path actualSize limit)
  | otherwise = Nothing
```

But there is no `maxArchiveExtractedBytes` constant.

## Files to Modify

### 1. `Canopy/Limits.hs` -- Add archive extraction limit

**Add** at the end of the file size limits section:

```haskell
-- | Maximum total extracted bytes from a package archive (200 MB).
--
-- Package archives should decompress to at most a few MB. This limit
-- provides protection against zip bombs while being generous enough
-- for any legitimate package.
--
-- @since 0.19.2
maxArchiveExtractedBytes :: Int
maxArchiveExtractedBytes = 200 * 1024 * 1024

-- | Maximum size of a single extracted file (50 MB).
--
-- No individual file in a package should be this large. Source files
-- are already limited to 10 MB by 'maxSourceFileBytes'; this limit
-- catches oversized assets and binary blobs.
--
-- @since 0.19.2
maxArchiveEntryBytes :: Int
maxArchiveEntryBytes = 50 * 1024 * 1024
```

**Also export** these from the module export list.

### 2. `File/Archive.hs` -- Add per-entry and cumulative size checks

**Strategy**: Check each entry's decompressed size BEFORE writing it. Also
track cumulative decompressed bytes across entries and abort if the total
exceeds the limit.

The `Codec.Archive.Zip` library's `Zip.Entry` has `eUncompressedSize :: Integer`
which reports the decompressed size from the ZIP directory. This can be checked
before decompression.

**Add a new error type**:

```haskell
-- | Errors during archive extraction.
data ArchiveError
  = EntryTooLarge !FilePath !Int !Int
  | TotalExtractionTooLarge !Int !Int
  deriving (Eq, Show)
```

**Add a pre-check function**:

```haskell
-- | Check whether a single entry exceeds the per-file size limit.
checkEntrySize :: Zip.Entry -> FilePath -> Either ArchiveError ()
checkEntrySize entry relativePath
  | entrySize > fromIntegral Limits.maxArchiveEntryBytes =
      Left (EntryTooLarge relativePath (fromIntegral entrySize) Limits.maxArchiveEntryBytes)
  | otherwise = Right ()
  where
    entrySize = Zip.eUncompressedSize entry
```

**Modify `writePackage`** to track cumulative size using an `IORef`:

```haskell
writePackage :: FilePath -> Zip.Archive -> IO ()
writePackage destination archive =
  case Zip.zEntries archive of
    [] -> pure ()
    allEntries@(firstEntry : _) -> do
      checkDestinationExists destination
      let rootDepth = calculateRootDepth firstEntry
      totalRef <- IORef.newIORef (0 :: Int)
      Foldable.traverse_ (writeEntrySafe destination rootDepth totalRef) allEntries
```

**New `writeEntrySafe`**:

```haskell
writeEntrySafe :: FilePath -> Int -> IORef.IORef Int -> Zip.Entry -> IO ()
writeEntrySafe destination rootDepth totalRef entry = do
  let relativePath = extractRelativePath rootDepth entry
      allowed = isAllowedPath relativePath && isWithinDestination destination relativePath
      entrySize = fromIntegral (Zip.eUncompressedSize entry)
  Monad.when allowed $ do
    enforceEntryLimit relativePath entrySize
    enforceTotalLimit totalRef entrySize
    writeEntryContent destination relativePath entry

enforceEntryLimit :: FilePath -> Int -> IO ()
enforceEntryLimit relativePath entrySize =
  Monad.when (entrySize > Limits.maxArchiveEntryBytes) $
    ioError (userError ("Archive entry too large: " <> relativePath
      <> " (" <> show entrySize <> " bytes, limit " <> show Limits.maxArchiveEntryBytes <> ")"))

enforceTotalLimit :: IORef.IORef Int -> Int -> IO ()
enforceTotalLimit totalRef entrySize = do
  currentTotal <- IORef.readIORef totalRef
  let newTotal = currentTotal + entrySize
  Monad.when (newTotal > Limits.maxArchiveExtractedBytes) $
    ioError (userError ("Archive extraction exceeds total size limit: "
      <> show newTotal <> " bytes (limit " <> show Limits.maxArchiveExtractedBytes <> ")"))
  IORef.writeIORef totalRef newTotal
```

### 3. `File/Archive.hs` -- Same changes for `writePackageReturnCanopyJson`

Apply the same IORef-based cumulative tracking and per-entry checking to the
`writePackageReturnCanopyJson` path (lines 127-135) and its helper
`writeEntryReturnCanopyJson` (lines 276-282).

### 4. Add `IORef` import

```haskell
import qualified Data.IORef as IORef
import qualified Canopy.Limits as Limits
```

## Verification

### Unit Tests

Add tests in a new `test/Unit/File/ArchiveTest.hs`:

1. **Test normal extraction works**: Create a small test ZIP with valid entries,
   extract with `writePackage`, verify files are written.

2. **Test per-entry limit**: Create a ZIP entry with `eUncompressedSize` larger
   than 50 MB, verify extraction throws an error.

3. **Test cumulative limit**: Create a ZIP with many entries whose total
   decompressed size exceeds 200 MB, verify extraction throws after the
   threshold.

4. **Test small archive passes**: Verify that normal-sized archives
   (few KB) pass both checks without issue.

### Commands

```bash
# Build
stack build

# Run all tests
stack test

# Run archive-specific tests
stack test --ta="--pattern Archive"
```
