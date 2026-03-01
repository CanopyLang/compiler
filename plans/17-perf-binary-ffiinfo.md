# Plan 17: Binary FFIInfo Round-Trip Fix

**Priority:** MEDIUM
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

The `Binary` instance for `FFIInfo` in `Generate/JavaScript.hs:83–92` serializes `Text` by round-tripping through `String`:

```haskell
put (FFIInfo path content alias) = do
    Binary.put path
    Binary.put (Text.unpack content)   -- Text → [Char] → Binary
    Binary.put alias
get = do
    path <- Binary.get
    contentStr <- Binary.get            -- Binary → [Char]
    alias <- Binary.get
    return (FFIInfo path (Text.pack contentStr) alias)  -- [Char] → Text
```

The full round-trip is `Text → [Char] → ByteString → [Char] → Text`. Each conversion allocates O(n) memory where n is the FFI file content size. This happens on every cache read/write for every FFI-using module.

## Fix

Serialize `Text` directly as UTF-8 bytes:

```haskell
instance Binary.Binary FFIInfo where
  put (FFIInfo path content alias) = do
    Binary.put path
    Binary.put (Text.encodeUtf8 content)  -- Text → ByteString (near zero-copy)
    Binary.put alias
  get = do
    path <- Binary.get
    contentBytes <- Binary.get             -- ByteString directly
    alias <- Binary.get
    return (FFIInfo path (Text.decodeUtf8 contentBytes) alias)
```

## Files to Modify

- `packages/canopy-core/src/Generate/JavaScript.hs` — lines 83–92

## Cache Compatibility

This changes the binary format for FFI info. Since the ELCO header has a schema version, bump the schema version in `Compiler/Cache.hs` to force recompilation of cached FFI modules. Old caches will get the "schema version mismatch" message and rebuild automatically.

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Compile an FFI project, verify cache is written
4. Compile again, verify cache is read successfully
5. Delete `canopy-stuff/`, recompile, verify clean build works
