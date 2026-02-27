# Plan 09 — Eliminate Triple-Parse per Module

**Priority:** Tier 1 (Critical Architecture)
**Effort:** 2 days
**Risk:** High (touches compilation pipeline core)
**Files:** `packages/canopy-builder/src/Compiler.hs`, `packages/canopy-driver/src/Driver.hs`, `packages/canopy-query/src/Parse/Cache.hs`

---

## Problem

Each source file is parsed up to 3 times per build:

1. **`discoverTransitiveDeps`** (Compiler.hs:192) — parses every file via `parseModuleFile` to extract imports for dependency discovery
2. **`parseModuleImports`** (Compiler.hs:288) — parses each file again to build the dependency graph for level-parallel grouping
3. **`Driver.runParsePhase`** (Driver.hs:153) — parses the file a third time during actual compilation

The `QueryEngine` is passed through but only tracks phase execution counts, not cached parse results.

**Impact:** At 1,000 modules, this wastes ~10 seconds of sequential I/O. At 5,000 modules, ~50 seconds. This is the single largest scaling bottleneck.

## Design

### Parse Cache Architecture

Introduce a `Map FilePath (ByteString, Src.Module)` that caches parse results keyed on `(filePath, contentHash)`. The cache sits in `IORef` and is shared across all three parse points.

```haskell
data ParseResult = ParseResult
  { _prContentHash :: !BS.ByteString   -- SHA-256 of source content
  , _prSourceAST   :: !Src.Module      -- parsed AST
  , _prImports     :: ![Src.Import]    -- extracted imports (for fast access)
  } deriving (Show)

type ParseCache = Map FilePath ParseResult
```

### Invariant

A cache entry is valid if and only if the file's content hash matches `_prContentHash`. Since files don't change during a single build invocation, a cache entry created in phase 1 is valid for phases 2 and 3.

## Implementation

### Step 1: Create ParseCache module (or extend existing Parse/Cache.hs)

`packages/canopy-query/src/Parse/Cache.hs` already exists but may not be wired into the hot path. Read it first:

```bash
cat packages/canopy-query/src/Parse/Cache.hs
```

If it provides the right interface, wire it in. If not, extend it:

```haskell
module Parse.Cache
  ( ParseCache
  , emptyCache
  , lookupOrParse
  , getCachedImports
  ) where

-- | Look up a cached parse result, or parse the file and cache it.
lookupOrParse
  :: IORef ParseCache
  -> FilePath
  -> IO (Either Error Src.Module)
lookupOrParse cacheRef path = do
  content <- BS.readFile path
  let hash = SHA256.hash content
  cache <- readIORef cacheRef
  case Map.lookup path cache of
    Just pr | _prContentHash pr == hash ->
      pure (Right (_prSourceAST pr))
    _ -> do
      case Parse.fromByteString content of
        Left err -> pure (Left err)
        Right ast -> do
          let pr = ParseResult hash ast (Src._imports ast)
          atomicModifyIORef' cacheRef (\c -> (Map.insert path pr c, ()))
          pure (Right ast)
```

Note: use `atomicModifyIORef'` for thread safety since parallel workers may access this cache.

### Step 2: Thread ParseCache through the pipeline

In `Compiler.hs`, create the cache once at the start of `compileFromPaths`:

```haskell
compileFromPaths :: ... -> IO (Either Exit CompileResult)
compileFromPaths opts paths = do
  parseCacheRef <- newIORef Parse.Cache.emptyCache
  -- Pass parseCacheRef to all three phases
  ...
```

### Step 3: Update discoverTransitiveDeps

Replace `parseModuleFile` with `Parse.Cache.lookupOrParse parseCacheRef`:

```haskell
-- Before: parseModuleFile path
-- After:  Parse.Cache.lookupOrParse parseCacheRef path
```

### Step 4: Update parseModuleImports

Replace the second parse with a cache lookup:

```haskell
-- Before: content <- BS.readFile path; case Parse.fromByteString content of ...
-- After:  Parse.Cache.getCachedImports parseCacheRef path
```

Since imports were already extracted in phase 1, this should be a pure `Map.lookup` — no file I/O at all.

### Step 5: Update Driver.runParsePhase

Replace the third parse with a cache lookup:

```haskell
-- Before: Parse.fromByteString <$> BS.readFile path
-- After:  Parse.Cache.lookupOrParse parseCacheRef path
```

### Step 6: Measure improvement

Add timing instrumentation (temporary) around each phase:

```haskell
t0 <- getCurrentTime
result <- discoverTransitiveDeps ...
t1 <- getCurrentTime
-- Log (t1 - t0)
```

Compare before/after on a project with 100+ modules.

## Edge Cases

1. **File modified during build:** The content hash check catches this — the cache entry won't match and the file will be re-parsed. This is correct.

2. **Memory pressure from cached ASTs:** For 10,000 modules, the cache holds 10,000 `Src.Module` values in memory. Each is roughly proportional to the source file size. For a total codebase of 1M lines, this is manageable (tens of MB). If needed, the cache can be made an LRU with a size limit.

3. **Thread safety:** `atomicModifyIORef'` is sufficient since each path is parsed at most once (the first access creates the entry, subsequent accesses read it).

## Validation

```bash
make build && make test
```

All 2,376 tests must pass. Additionally, build a test project with 50+ modules and verify:
- The log shows each file parsed exactly once
- Build time decreases measurably vs baseline

## Acceptance Criteria

- Each source file is parsed at most once per build invocation
- No regression in compilation correctness
- `make build && make test` passes
- Measurable build time improvement on projects with 50+ modules
