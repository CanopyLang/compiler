# Plan 51: Resilient Package Fetching with GitHub Fallback

## Priority: CRITICAL
## Effort: Large (3-5 days)
## Risk: Medium — changes core dependency resolution pipeline

## Problem

Canopy currently depends on `package.elm-lang.org` as a **single point of failure** for package resolution. When Elm's registry is down (which happens frequently), `canopy install` fails completely — there is no automatic package download from any source, and no fallback.

### Current State (from deep research)

1. **Registry**: Hardcoded to `https://package.elm-lang.org/all-packages` in `packages/canopy-terminal/src/Deps/Registry.hs` (line 118). Returns JSON mapping `"author/project"` to version arrays.

2. **No automatic package download**: Unlike Elm's compiler which fetches packages via `endpoint.json` → GitHub ZIP, Canopy has **no package download implementation**. It relies entirely on:
   - Copying from Elm's cache (`~/.elm/0.19.1/packages/`) via `canopy setup`
   - Manually placing packages in `~/.canopy/packages/`

3. **HTTP infrastructure exists but is underused**: `packages/canopy-builder/src/Http.hs` has full `getArchive`/`getArchiveWithFallback` with SHA-256 verification and ZIP streaming — but nothing calls it for package installation.

4. **Fallback is string replacement only**: `fallbackToElmUrl` in Http.hs does `canopy-lang.org` → `elm-lang.org` text substitution. No fallback to direct source (GitHub).

5. **Lock file records hashes but not source URLs**: `Builder/LockFile.hs` stores SHA-256 hashes per package but no download URL or git repo info.

6. **Custom repository types exist but are stubbed**: `CustomRepositoryData.hs` has `DefaultPackageServerRepoData` and `PZRPackageServerRepoData` types but `loadCustomRepositoriesData` always returns `mempty`.

### How Other Ecosystems Solve This

| Ecosystem | Approach | Registry Down Behavior |
|-----------|----------|----------------------|
| **Go** | Proxy chain (`GOPROXY=proxy.golang.org,direct`). Falls back to direct VCS (git) fetch. | Works — fetches directly from GitHub/GitLab |
| **Cargo/Rust** | Git index (mirrorable) + sparse HTTP. `cargo vendor` for offline. | Works offline if index was cloned. No auto git fallback. |
| **Zig** | No registry. URL + content hash in `build.zig.zon`. Multiple mirrors per package. | Works if any mirror is up. |
| **npm** | Content-addressed cache. Verdaccio as local proxy. | Works for cached packages. No git fallback. |
| **Elm** | Single registry. `endpoint.json` → GitHub ZIP. | **Fails completely** — same problem as Canopy. |
| **Nix** | Git repo (nixpkgs) + binary caches. Content-addressed store. | Works — builds from source if cache is down. |

**Key insight from Go**: URLs/git should be a **fallback**, not the primary mechanism. A registry provides discoverability and speed. Direct git fetch provides resilience.

**Key insight from Zig**: Content-addressed packages (identified by hash, not URL) are inherently mirrorable and verifiable.

**Embedding git URLs is NOT an anti-pattern** — it's standard practice in Go, Zig, Nix, and npm. The pattern is: registry first → direct source as fallback.

## Implementation Plan

### Step 1: Implement actual package downloading

**File**: `packages/canopy-builder/src/PackageCache/Fetch.hs` (NEW)

This is the biggest gap — Canopy currently has NO way to download packages. All Elm packages are on GitHub (it's a requirement for `elm publish`), so the URL pattern is known:

```haskell
-- | Fetch a package archive from the registry or GitHub.
--
-- Resolution order:
-- 1. Local cache (~/.canopy/packages/{author}/{project}/{version}/)
-- 2. Elm cache (~/.elm/0.19.1/packages/{author}/{project}/{version}/)
-- 3. Registry endpoint (package.elm-lang.org/packages/{pkg}/{ver}/endpoint.json)
-- 4. Direct GitHub fetch (github.com/{author}/{project}/zipball/{version}/)

data FetchSource
  = CachedLocal !FilePath
  | CachedElm !FilePath
  | FetchedRegistry !Text  -- URL from endpoint.json
  | FetchedGitHub !Text    -- Direct GitHub URL

fetchPackage :: Http.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
fetchPackage manager pkg ver = do
  -- 1. Check local cache
  localResult <- checkLocalCache pkg ver
  case localResult of
    Just path -> pure (Right (CachedLocal path))
    Nothing -> do
      -- 2. Check Elm cache
      elmResult <- checkElmCache pkg ver
      case elmResult of
        Just path -> pure (Right (CachedElm path))
        Nothing -> fetchFromNetwork manager pkg ver

fetchFromNetwork :: Http.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
fetchFromNetwork manager pkg ver = do
  -- 3. Try registry endpoint.json
  registryResult <- fetchViaEndpoint manager pkg ver
  case registryResult of
    Right source -> pure (Right source)
    Left _ -> do
      -- 4. Fall back to direct GitHub
      fetchFromGitHub manager pkg ver
```

### Step 2: Implement endpoint.json fetching (Elm compatibility)

**File**: `packages/canopy-builder/src/PackageCache/Fetch.hs`

Elm's registry serves `endpoint.json` files that contain the actual download URL and hash:

```
GET https://package.elm-lang.org/packages/{author}/{project}/{version}/endpoint.json
→ {"url": "https://github.com/{author}/{project}/zipball/{version}/", "hash": "sha256:..."}
```

```haskell
fetchViaEndpoint :: Http.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
fetchViaEndpoint manager pkg ver = do
  let endpointUrl = registryBase ++ "/packages/" ++ Pkg.toChars pkg ++ "/" ++ Version.toChars ver ++ "/endpoint.json"
  result <- Http.get manager endpointUrl
  case result of
    Left err -> pure (Left (RegistryUnavailable err))
    Right bs -> do
      let endpoint = Json.decode bs  -- {url, hash}
      downloadAndVerify manager (endpointUrl endpoint) (endpointHash endpoint) pkg ver
```

### Step 3: Implement direct GitHub fetch (fallback)

**File**: `packages/canopy-builder/src/PackageCache/Fetch.hs`

Since all Elm packages are GitHub repos, the URL pattern is deterministic:

```haskell
fetchFromGitHub :: Http.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
fetchFromGitHub manager pkg ver = do
  let (author, project) = Pkg.toAuthorProject pkg
      zipUrl = "https://github.com/" ++ author ++ "/" ++ project ++ "/zipball/" ++ Version.toChars ver ++ "/"
  Log.logEvent (PackageOperation "github-fetch" (Text.pack zipUrl))
  IO.hPutStrLn IO.stderr ("  Fetching " ++ Pkg.toChars pkg ++ " " ++ Version.toChars ver ++ " from GitHub...")
  result <- Http.getArchive manager zipUrl
  case result of
    Left err -> pure (Left (GitHubUnavailable err))
    Right archive -> do
      extractAndCache archive pkg ver
      pure (Right (FetchedGitHub (Text.pack zipUrl)))
```

### Step 4: Add git URL metadata to lock file

**File**: `packages/canopy-builder/src/Builder/LockFile.hs`

Extend `LockedPackage` to record where the package was fetched from, enabling future resilience:

```haskell
data LockedPackage = LockedPackage
  { _lpVersion :: !Version.Version
  , _lpHash :: !Text.Text
  , _lpDependencies :: !(Map Pkg.Name Version.Version)
  , _lpSignature :: !(Maybe PackageSignature)
  , _lpSource :: !(Maybe PackageSource)  -- NEW
  }

data PackageSource = PackageSource
  { _psGitUrl :: !Text          -- "https://github.com/elm/core"
  , _psArchiveUrl :: !(Maybe Text) -- "https://github.com/elm/core/zipball/1.0.5/"
  }
```

This means once a package is resolved, the lock file knows where to fetch it from even if the registry is completely gone.

### Step 5: Wire fetch into `canopy install`

**File**: `packages/canopy-terminal/src/Install/Execution.hs`

After the solver resolves versions, actually download missing packages before verification:

```haskell
performInstallation ctx scope = do
  let root = ctx ^. icRoot
      newOutline = ctx ^. icNewOutline
      resolvedDeps = extractResolvedDeps newOutline

  -- Download any packages not in cache
  manager <- Http.getManager
  fetchResults <- traverse (fetchIfMissing manager) (Map.toList resolvedDeps)
  case partitionEithers fetchResults of
    ([], _) -> do
      -- All packages available, proceed with verification
      Outline.write root newOutline
      result <- Details.verifyInstall scope root env newOutline
      ...
    (errors, _) ->
      reportFetchErrors errors
```

### Step 6: Add `--offline` flag

**File**: `packages/canopy-terminal/src/CLI/Commands.hs`

Add `--offline` flag that skips all network requests and uses only cached packages:

```
canopy install --offline    # Only use local cache
canopy build --offline      # Build with cached deps only
```

### Step 7: Add `canopy vendor` command

**File**: `packages/canopy-terminal/src/Vendor.hs` (NEW)

Copy all resolved dependencies into a `vendor/` directory for fully offline builds:

```
canopy vendor              # Copy deps to ./vendor/
canopy build --vendor      # Build using ./vendor/ instead of global cache
```

This is the ultimate resilience measure for CI/CD and air-gapped environments.

### Step 8: Registry caching with TTL

**File**: `packages/canopy-terminal/src/Deps/Registry.hs`

Instead of fetching the full registry on every `install`, cache it with a TTL:

```haskell
-- Only fetch fresh registry if cache is older than 1 hour
registryCacheTTL :: NominalDiffTime
registryCacheTTL = 3600

latestWithCache :: Manager -> FilePath -> IO (Either String Registry)
latestWithCache manager cache = do
  age <- registryCacheAge cache
  if age < registryCacheTTL
    then readCachedRegistry cache
    else fetchAndCache manager cache
```

### Step 9: Content-addressed package cache

Align the local cache with content-addressing (like Go/Zig) for integrity:

```
~/.canopy/packages/
  registry.dat              # Binary-cached registry
  sha256/
    abc123.../              # Content-addressed package directories
      canopy.json
      src/
      artifacts.dat
  by-name/
    elm/core/1.0.5 -> ../../sha256/abc123.../  # Symlinks for convenience
```

This makes the cache inherently deduplicatable and verifiable.

### Step 10: Tests

- Test local cache hit (no network)
- Test Elm cache fallback
- Test endpoint.json fetch
- Test GitHub direct fetch fallback
- Test --offline mode (reject network requests)
- Test vendor command creates correct directory
- Test registry TTL caching
- Test lock file source URL recording
- Integration test: install with registry down, verify GitHub fallback works

## Architecture Summary

```
canopy install elm/http

1. Solve constraints (registry from cache or network)
2. For each resolved package:
   a. Check ~/.canopy/packages/ (local cache)         → DONE
   b. Check ~/.elm/0.19.1/packages/ (Elm cache)       → copy to local, DONE
   c. Fetch endpoint.json from registry                → download ZIP, verify hash, DONE
   d. Fetch ZIP directly from GitHub                   → download, extract, DONE
   e. All sources failed                               → ERROR with helpful message
3. Verify all packages (hashes, signatures)
4. Write lock file with source URLs
5. Build
```

## Dependencies
- Plan 02 (timing-safe comparison) for hash verification
- Plan 03 (registry fallback transparency) for user-visible fallback notifications
- Plan 14 (newtypes) for ContentHash type in verification
