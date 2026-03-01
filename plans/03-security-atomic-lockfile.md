# Plan 03: Atomic Lock File Writes

- **Priority**: HIGH
- **Effort**: Small (1-2h)
- **Risk**: Low

## Problem

The lock file (`canopy.lock`) is written with a plain `LBS.writeFile` call.
If the process is killed, the system loses power, or the disk fills up during
the write, the lock file will be left in a corrupted partial state. On the next
`canopy install`, the corrupted file will fail to parse, requiring the user to
manually delete it.

The codebase already has a robust atomic write utility (`File.Atomic`) that uses
the write-to-temp-then-rename pattern. It is already used for critical files
during archive extraction, but NOT for the lock file.

### Current Code -- Non-Atomic Lock File Write

**File**: `/home/quinten/fh/canopy/packages/canopy-builder/src/Builder/LockFile.hs`

At lines 160-164, `writeLockFile` uses plain `LBS.writeFile`:

```haskell
writeLockFile :: FilePath -> LockFile -> IO ()
writeLockFile root lf = do
  let path = lockFilePath root
  Log.logEvent (PackageOperation "lock-write" (Text.pack path))
  LBS.writeFile path (Json.encode lf)
```

**File**: `/home/quinten/fh/canopy/packages/canopy-builder/src/Builder/LockFile/Generate.hs`

At lines 71-73, `generateLockFile` also uses plain `LBS.writeFile`:

```haskell
  let path = root </> "canopy.lock"
  Log.logEvent (PackageOperation "lock-write" (Text.pack path))
  LBS.writeFile path (Json.encode lf)
```

### Existing Atomic Write Utility

**File**: `/home/quinten/fh/canopy/packages/canopy-core/src/File/Atomic.hs`

The `writeLazyBytesAtomic` function (lines 156-167) does exactly what we need:

```haskell
writeLazyBytesAtomic :: FilePath -> LBS.ByteString -> IO ()
writeLazyBytesAtomic targetPath content = do
  ensureAtomicDirectory targetPath
  withTempFile targetPath $ \tempPath -> do
    IO.withBinaryFile tempPath IO.WriteMode $ \handle -> do
      IO.hSetBuffering handle (IO.BlockBuffering Nothing)
      LBS.hPut handle content
      IO.hFlush handle
      IO.hClose handle
    atomicRename tempPath targetPath
```

It already handles:
- Writing to a temporary file in the same directory
- Flushing to disk before rename
- Atomic rename (with cross-device fallback)
- Cleanup of temporary file on failure

## Files to Modify

### 1. `Builder/LockFile.hs` (lines 160-164)

**Current**:
```haskell
writeLockFile :: FilePath -> LockFile -> IO ()
writeLockFile root lf = do
  let path = lockFilePath root
  Log.logEvent (PackageOperation "lock-write" (Text.pack path))
  LBS.writeFile path (Json.encode lf)
```

**Proposed**:
```haskell
writeLockFile :: FilePath -> LockFile -> IO ()
writeLockFile root lf = do
  let path = lockFilePath root
  Log.logEvent (PackageOperation "lock-write" (Text.pack path))
  Atomic.writeLazyBytesAtomic path (Json.encode lf)
```

**Add import**:
```haskell
import qualified File.Atomic as Atomic
```

### 2. `Builder/LockFile/Generate.hs` (lines 71-73)

**Current**:
```haskell
  let path = root </> "canopy.lock"
  Log.logEvent (PackageOperation "lock-write" (Text.pack path))
  LBS.writeFile path (Json.encode lf)
```

**Proposed**:
```haskell
  let path = root </> "canopy.lock"
  Log.logEvent (PackageOperation "lock-write" (Text.pack path))
  Atomic.writeLazyBytesAtomic path (Json.encode lf)
```

**Add import**:
```haskell
import qualified File.Atomic as Atomic
```

**Possibly remove unused import** of `Data.ByteString.Lazy` if `LBS.writeFile`
was the only usage (check for other `LBS.` references first -- `LBS.readFile` is
not used in Generate.hs, but double-check).

### 3. Verify `File.Atomic` is accessible from `canopy-builder`

Check whether `canopy-builder.cabal` already depends on `canopy-core` (which
provides `File.Atomic`). If not, add the dependency.

**File**: `/home/quinten/fh/canopy/packages/canopy-builder/canopy-builder.cabal`

Search for `canopy-core` in the `build-depends` section. If it is already listed,
no change is needed. If not, add:

```
  build-depends:
    , canopy-core
```

## Verification

### Manual Test

1. Build the project with `stack build`.
2. Run `canopy install` in a test project.
3. While the lock file is being written, kill the process (`Ctrl-C` or
   `kill -9`).
4. Verify that the lock file is either:
   - Fully intact (the rename completed), or
   - Absent (the rename did not happen yet, but no partial file exists).
5. Running `canopy install` again should succeed without manual cleanup.

### Unit Tests

The atomic write utility is already tested by its own tests. The change here is
purely a substitution of `LBS.writeFile` with `Atomic.writeLazyBytesAtomic`,
so existing lock file tests cover the functional behavior. Verify:

```bash
# Build
stack build

# Run all tests
stack test

# Run lockfile-specific tests
stack test --ta="--pattern LockFile"
```
