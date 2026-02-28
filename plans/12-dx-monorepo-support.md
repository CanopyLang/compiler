# Plan 12: Monorepo / Workspace Support

## Priority: MEDIUM
## Effort: Large (3-5 days)
## Risk: Medium — new feature touching outline parsing and build system

## Problem

`AppOutline` has no workspace/packages fields. Teams with multiple related packages must manage them as separate projects with duplicated dependency declarations. No way to share local packages within a workspace.

### Current Code (packages/canopy-core/src/Canopy/Outline.hs)

```haskell
data AppOutline = AppOutline
  { _appCanopyVersion :: !Version
  , _appSourceDirs :: ![FilePath]  -- No workspace concept
  , _appDepsDirect :: !(Map Pkg.Name Version)
  , _appDepsIndirect :: !(Map Pkg.Name Version)
  , _appTestDepsDirect :: !(Map Pkg.Name Version)
  , _appTestDepsIndirect :: !(Map Pkg.Name Version)
  }
```

## Implementation Plan

### Step 1: Define workspace format in canopy.json

```json
{
    "type": "workspace",
    "packages": [
        "packages/core",
        "packages/ui",
        "packages/server"
    ],
    "shared-dependencies": {
        "elm/core": "1.0.5"
    }
}
```

### Step 2: Add Workspace outline type

**File**: `packages/canopy-core/src/Canopy/Outline.hs`

```haskell
data Outline
  = App AppOutline
  | Pkg PkgOutline
  | Workspace WorkspaceOutline  -- NEW

data WorkspaceOutline = WorkspaceOutline
  { _wsPackages :: ![FilePath]
  , _wsSharedDeps :: !(Map Pkg.Name Version)
  , _wsCanopyVersion :: !Version
  }
```

### Step 3: Workspace discovery

**File**: `packages/canopy-builder/src/Builder/Workspace.hs` (NEW)

- Walk up directory tree to find workspace root
- `findWorkspaceRoot :: FilePath -> IO (Maybe FilePath)`
- `resolveWorkspacePackages :: WorkspaceOutline -> IO [PackageInfo]`

### Step 4: Cross-package local dependencies

Allow packages within a workspace to depend on each other by path:

```json
{
    "type": "package",
    "dependencies": {
        "my-org/core": "local:../core"
    }
}
```

### Step 5: Shared dependency resolution

When building within a workspace, use the workspace's shared dependencies as constraints. Individual packages can add but not conflict with workspace deps.

### Step 6: Build orchestration

**File**: `packages/canopy-builder/src/Builder/Workspace.hs`

- Detect which packages changed
- Build in dependency order
- Share compilation artifacts between workspace packages

### Step 7: CLI integration

- `canopy build` in workspace root builds all packages
- `canopy build --package=core` builds specific package
- `canopy test` in workspace root runs all tests

### Step 8: Tests

- Test workspace discovery
- Test shared dependency resolution
- Test cross-package local dependencies
- Test partial workspace builds
- Test conflict detection between workspace and package deps

## Dependencies
- None (but benefits from Plan 06 bounded parallelism)
