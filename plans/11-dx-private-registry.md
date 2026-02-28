# Plan 11: Private Registry Support

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Medium — affects dependency resolution

## Problem

The registry URL is hardcoded in `Deps/Registry.hs` as `"https://package.elm-lang.org/all-packages"`. `CustomRepositoriesData` is accepted by `latest` but ignored. Enterprise users and teams cannot host private packages.

### Current Code (packages/canopy-builder/src/Deps/Registry.hs)

```haskell
-- Lines 119-120
registryUrl :: String
registryUrl = "https://package.elm-lang.org/all-packages"

-- latest accepts CustomRepositoriesData but ignores it
latest :: Manager -> CustomRepositoriesData -> FilePath -> FilePath -> IO (Either String Registry)
```

## Implementation Plan

### Step 1: Make registry URL configurable

**File**: `packages/canopy-builder/src/Deps/Registry.hs`

```haskell
data RegistryConfig = RegistryConfig
  { _registryPrimary :: !Text      -- Primary registry URL
  , _registryFallback :: !(Maybe Text)  -- Optional fallback
  , _registryAuth :: !(Maybe AuthToken) -- Optional auth for private registries
  }

defaultConfig :: RegistryConfig
defaultConfig = RegistryConfig
  { _registryPrimary = "https://package.elm-lang.org/all-packages"
  , _registryFallback = Nothing
  , _registryAuth = Nothing
  }
```

### Step 2: Add canopy.json registry configuration

**File**: `packages/canopy-core/src/Canopy/Outline.hs`

Support in canopy.json:
```json
{
    "registries": [
        "https://packages.mycompany.com",
        "https://package.elm-lang.org"
    ]
}
```

### Step 3: Add environment variable support

Support `CANOPY_REGISTRY_URL` and `CANOPY_REGISTRY_TOKEN` environment variables for CI/CD integration.

### Step 4: Registry fallback chain

When multiple registries are configured, try them in order:
1. First configured registry
2. Second configured registry
3. Default public registry (if not disabled)

### Step 5: Authentication support

**File**: `packages/canopy-builder/src/Deps/Registry/Auth.hs` (NEW)

- Support Bearer token authentication
- Read token from environment, config file, or credential helper
- `withAuth :: RegistryConfig -> Request -> Request`

### Step 6: CLI flags

Add `--registry <url>` and `--registry-token <token>` flags.

### Step 7: Tests

- Test custom registry URL resolution
- Test authentication header injection
- Test fallback chain behavior
- Test environment variable override
- Test canopy.json registry field parsing

## Dependencies
- Plan 03 (registry fallback transparency)
