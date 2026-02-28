# Plan 03: Registry Fallback Transparency & User Consent

## Priority: HIGH
## Effort: Medium (1-2 days)
## Risk: Medium — affects package resolution behavior

## Problem

When `canopy-lang.org` is unreachable, `Http.hs` silently falls back to `elm-lang.org` via hardcoded string replacement. Users have no visibility into this, creating a supply-chain risk: packages could differ between registries.

### Current Code (packages/canopy-builder/src/Http.hs)

```haskell
-- Lines 235-250: Silent URL replacement
fallbackToElmUrl :: String -> String
fallbackToElmUrl url =
  Text.unpack (Text.replace "canopy-lang.org" "elm-lang.org" (Text.pack url))

-- Lines 340-351: Silent fallback with only log event
getWithFallback :: Manager -> String -> IO (Either String ByteString)
getWithFallback manager url = do
  result <- get manager url
  case result of
    Right bs -> pure (Right bs)
    Left _ -> do
      Log.logEvent (NetworkFallback url (fallbackToElmUrl url))
      get manager (fallbackToElmUrl url)
```

## Implementation Plan

### Step 1: Add user-visible fallback notification

**File**: `packages/canopy-builder/src/Http.hs`

Replace silent fallback with visible warning:

```haskell
getWithFallback :: Manager -> String -> IO (Either String ByteString)
getWithFallback manager url = do
  result <- get manager url
  case result of
    Right bs -> pure (Right bs)
    Left primaryErr -> do
      let fallbackUrl = fallbackToElmUrl url
      IO.hPutStrLn IO.stderr $
        "WARNING: canopy-lang.org unreachable, falling back to elm-lang.org"
      Log.logEvent (NetworkFallback url fallbackUrl)
      get manager fallbackUrl
```

### Step 2: Add --no-fallback CLI flag

**File**: `packages/canopy-terminal/src/CLI/Commands.hs`

Add a `--no-fallback` flag that prevents registry fallback entirely. When set, return the primary error instead of trying elm-lang.org.

**File**: `packages/canopy-builder/src/Http.hs`

Thread a `FallbackPolicy` (enum: `AllowFallback | DenyFallback`) through the HTTP functions.

### Step 3: Add --registry flag for custom registry URL

**File**: `packages/canopy-terminal/src/CLI/Commands.hs`

Add `--registry <url>` flag to override the default registry URL entirely.

**File**: `packages/canopy-builder/src/Deps/Registry.hs`

Replace hardcoded `registryUrl` (line 119-120) with configurable value:

```haskell
-- Current: registryUrl = "https://package.elm-lang.org/all-packages"
-- New: Accept URL from environment or CLI flag
registryUrl :: Maybe String -> String
registryUrl (Just custom) = custom
registryUrl Nothing = "https://package.elm-lang.org/all-packages"
```

### Step 4: Add canopy.json registry field

**File**: `packages/canopy-core/src/Canopy/Outline.hs`

Add optional `"registry"` field to `AppOutline`:

```haskell
data AppOutline = AppOutline
  { ...
  , _appRegistry :: !(Maybe Text)  -- Custom registry URL
  }
```

### Step 5: Hash verification across registries

When fallback occurs, compare the SHA-256 hash of the downloaded package against the lock file hash. If they differ, warn the user loudly.

### Step 6: Tests

- Test fallback behavior with --no-fallback
- Test custom registry URL
- Test hash mismatch warning on fallback

## Dependencies
- Plan 02 (timing-safe comparison for hash verification)
