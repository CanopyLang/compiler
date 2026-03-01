# Plan 08: Binary Cache Version Verification

**Priority:** HIGH
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

The `.elco` cache format writes compiler version into the header (6 bytes: major/minor/patch as Word16) but `skipCompilerVersion` (Compiler/Cache.hs:274–277) simply skips over these bytes without checking them. A cache file from compiler 1.0.0 is treated identically to one from 2.0.0. This can cause silent deserialization failures or, worse, silently incorrect behavior if the Binary format of internal types changes without a schema version bump.

## Files to Modify

### `packages/canopy-builder/src/Compiler/Cache.hs`

1. **Replace `skipCompilerVersion` with `verifyCompilerVersion`**:
   ```haskell
   verifyCompilerVersion :: BS.ByteString -> Int -> Either String Int
   verifyCompilerVersion bs offset =
     let major = getWord16 bs offset
         minor = getWord16 bs (offset + 2)
         patch = getWord16 bs (offset + 4)
         expected = (currentMajor, currentMinor, currentPatch)
         actual = (major, minor, patch)
     in if expected == actual
       then Right (offset + 6)
       else Left ("cache compiled with v" ++ showVersion actual
                  ++ " but current compiler is v" ++ showVersion expected
                  ++ ". Run 'canopy make' to rebuild.")
   ```

2. **Update `decodeVersioned`** (line 241) to call `verifyCompilerVersion` and propagate the error

3. **On version mismatch**: Return `Left` with a clear message (don't crash), causing the build system to recompile from source

### `packages/canopy-core/src/Canopy/Version.hs`

Export `major`, `minor`, `patch` as individual `Word16` values for use in cache header verification.

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Add unit test: cache header with wrong compiler version returns descriptive error
4. Add unit test: cache header with correct compiler version decodes successfully
5. Manually verify: after bumping compiler version, old cache files trigger recompilation with clear message
