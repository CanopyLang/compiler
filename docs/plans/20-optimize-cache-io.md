# Plan 20 — Optimize Incremental Cache I/O

**Priority:** Tier 3 (Performance)
**Effort:** 1 day
**Risk:** Medium
**Files:** `packages/canopy-builder/src/Builder/Incremental.hs`, `packages/canopy-builder/src/Compiler.hs`, `packages/canopy-builder/src/Builder/Hash.hs`

---

## Problem

Several cache I/O patterns are unnecessarily expensive:

1. **`computeDepsHash`** (Compiler.hs:609-615) calls `Binary.encode iface` for every dependency interface on every build, even on cache hits. For a module with 30 imports each with 100KB interfaces, this hashes 3MB of binary data per module per build.

2. **`decodeCachedModule`** reads the artifact file once, and on failure reads it again for legacy format. Two `readFile` calls on the same path per legacy cache entry.

3. **`saveBuildCache`** serializes the entire JSON cache and writes it synchronously after every build, blocking the main thread.

4. **`invalidateTransitive`** uses `ms ++ deps` — O(N^2) list append at each recursive step.

## Implementation

### Fix 1: Cache interface hashes

Instead of re-encoding and re-hashing every dependency interface on every build, store the interface hash alongside the interface when it is first computed:

```haskell
-- In the compilation result, include the interface hash:
data ModuleResult = ModuleResult
  { mrInterface :: !Interface
  , mrInterfaceHash :: !HashValue   -- computed once, stored
  , mrLocalGraph :: !Opt.LocalGraph
  , mrFFIInfo :: !(Map JsSourcePath FFIInfo)
  }

-- computeDepsHash now just reads stored hashes:
computeDepsHash :: Map ModuleName.Raw ModuleResult -> ModuleName.Raw -> HashValue
computeDepsHash results modName =
  Hash.hashDependencies depHashes
  where
    depHashes = Map.mapMaybe (\dep -> mrInterfaceHash <$> Map.lookup dep results) (getDeps modName)
```

This reduces per-module-per-build work from O(sum of interface sizes) to O(number of deps x 32 bytes).

### Fix 2: Single-read cache decode with format detection

```haskell
decodeCachedModule :: FilePath -> IO (Maybe (Interface, Opt.LocalGraph, FFIInfo))
decodeCachedModule path = do
  bytes <- BS.readFile path  -- Read once
  case SchemaVersion.readHeader bytes of  -- From Plan 08
    SchemaVersion.HeaderOk ->
      decodeTriple (BS.drop 6 bytes)
    SchemaVersion.HeaderVersionMismatch _ ->
      pure Nothing  -- Stale, will rebuild
    SchemaVersion.HeaderCorrupt ->
      decodeLegacy bytes  -- Try legacy format on same bytes
  where
    decodeTriple bs = case Binary.decodeOrFail (BSL.fromStrict bs) of
      Right (_, _, result) -> pure (Just result)
      Left _ -> pure Nothing
    decodeLegacy bs = case Binary.decodeOrFail (BSL.fromStrict bs) of
      Right (_, _, (iface, graph)) -> pure (Just (iface, graph, Map.empty))
      Left _ -> pure Nothing
```

### Fix 3: Async cache save

```haskell
saveBuildCacheAsync :: IORef BuildCache -> FilePath -> IO ()
saveBuildCacheAsync cacheRef path = void $ Async.async $ do
  cache <- readIORef cacheRef
  let json = Aeson.encode cache
  BSL.writeFile (path <> ".tmp") json
  Dir.renameFile (path <> ".tmp") path  -- atomic replace
```

The async save uses a temp file + atomic rename to prevent corruption from concurrent reads.

### Fix 4: Replace list append in invalidateTransitive

```haskell
-- Before:
collectTransitive visited (ms ++ deps)  -- O(N^2)

-- After: Use a Set for the work queue
invalidateTransitive :: BuildCache -> [ModuleName.Raw] -> BuildCache
invalidateTransitive cache roots =
  go cache (Set.fromList roots) Set.empty
  where
    go cache pending visited
      | Set.null pending = cache
      | otherwise =
          let (current, rest) = Set.deleteFindMin pending
          in if Set.member current visited
            then go cache rest visited
            else
              let deps = getDependents cache current
                  cache' = removeCacheEntry cache current
              in go cache' (Set.union rest deps) (Set.insert current visited)
```

This eliminates the O(N^2) list concatenation entirely — the work queue is a `Set` with O(log N) operations.

## Validation

```bash
rm -rf canopy-stuff  # Clear cache for clean test
make build && make test
```

## Acceptance Criteria

- Interface hashes are computed once and stored, not re-computed per build
- Cache files are read once per decode attempt, not twice
- Build cache save is asynchronous with atomic file replacement
- `invalidateTransitive` uses `Set`-based work queue, not list append
- `make build && make test` passes
