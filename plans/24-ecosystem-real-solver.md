# Plan 24: Dependency Solver Replacement

**Priority:** HIGH
**Effort:** Large (3-5d)
**Risk:** Medium -- Two independent solver modules with different consumers; the pure Builder.Solver is unused at runtime, but the terminal Deps.Solver has real limitations

## Problem

The project contains two dependency solver modules with fundamentally different designs. Neither implements real dependency resolution. The pure solver (`Builder.Solver`) picks hard-coded versions without consulting any registry. The terminal solver (`Deps.Solver`) consults the registry but resolves each package independently without considering transitive dependency interactions.

### Builder.Solver: Toy Solver with Hard-Coded Versions

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Builder/Solver.hs` (247 lines)

This module has a complete API surface (`solve`, `solveWithConstraints`, `verifySolution`, `parseConstraint`, `satisfiesConstraint`) but its core resolution function picks versions without any registry lookup:

Lines 139-144 -- `pickVersion` returns hard-coded values for every constraint type:
```haskell
pickVersion :: Pkg.Name -> Constraint -> Maybe Version.Version
pickVersion _ AnyVersion = Just Version.one
pickVersion _ (ExactVersion v) = Just v
pickVersion _ (MinVersion v) = Just v
pickVersion _ (MaxVersion v) = Just v
pickVersion _ (RangeVersion _ maxV) = Just maxV
```

Key problems:
- `AnyVersion` always returns `Version.one` (1.0.0) regardless of what versions exist
- `MinVersion v` returns `v` itself instead of the highest available version satisfying `>= v`
- `MaxVersion v` returns `v` instead of the highest version satisfying `<= v`
- The `_` pattern on the `Pkg.Name` parameter means the package name is completely ignored -- no registry lookup at all
- The backtracking in `findSolution` (line 88-97) is structurally correct but meaningless because `pickVersion` never fails and never tries alternatives

Lines 88-97 -- Backtracking that never backtracks:
```haskell
findSolution :: Solution -> [(Pkg.Name, [Constraint])] -> Maybe Solution
findSolution solution [] = Just solution
findSolution solution ((pkg, constraints) : rest) =
  case selectVersion pkg constraints of
    Nothing -> Nothing
    Just version ->
      let solution' = Map.insert pkg version solution
       in if isCompatible solution' rest
            then findSolution solution' rest
            else Nothing
```

Since `pickVersion` always returns `Just`, `selectVersion` only fails when `combineConstraints` fails (incompatible constraint types). The solver never considers multiple candidate versions.

**Usage:** `Builder.Solver` is imported by `Builder.hs` (line 66) but only for the `SolverError` type in the `BuildError` sum type (line 98). The solver's `solve` function is never called from production code -- only from tests.

### Deps.Solver: Registry-Aware but Non-Transitive

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Deps/Solver.hs` (162 lines)

This is the real solver used by the CLI. It consults the package registry but resolves each package independently:

Lines 103-117 -- `resolveConstraints` resolves each package in isolation:
```haskell
resolveConstraints ::
  Registry.CanopyRegistries ->
  [(Pkg.Name, Constraint.Constraint)] ->
  Maybe (Map Pkg.Name Details)
resolveConstraints registry = fmap Map.fromList . traverse (resolveOne registry)

resolveOne ::
  Registry.CanopyRegistries ->
  (Pkg.Name, Constraint.Constraint) ->
  Maybe (Pkg.Name, Details)
resolveOne registry (pkg, constraint) = do
  Registry.KnownVersions latest older <- Registry.getVersions' registry pkg
  version <- findSatisfying constraint (latest : older)
  Just (pkg, Details version Map.empty)
```

Key problems:

1. **No transitive dependency resolution.** `resolveOne` returns `Details version Map.empty` (line 117) -- the dependency map of each resolved package is always empty. Real dependency resolution must fetch each package's own dependencies and recursively satisfy them.

2. **No version conflict detection.** If package A requires `elm/json >= 1.0.0 < 2.0.0` and package B requires `elm/json >= 2.0.0 < 3.0.0`, the solver does not detect this conflict because it never sees that both A and B depend on `elm/json`.

3. **No backtracking.** `findSatisfying` (lines 157-161) picks the first (highest) version satisfying a constraint. If that version's transitive dependencies conflict, there is no mechanism to try a lower version.

4. **`Connection` type is a unit.** Line 37: `type Connection = ()`. This was intended to carry network state for online/offline resolution but is unused.

5. **`SolverResult` has redundant constructors.** Lines 55-62:
```haskell
data SolverResult a
  = Err String
  | NoSolution
  | NoOfflineSolution [Pkg.Name]
  | Ok a
  | Online a
  | Offline a
```
`Ok`, `Online`, and `Offline` carry the same payload and are handled identically by all consumers (see `Install/AppPlan.hs` lines 213-218, `Install/PkgPlan.hs` lines 195-197, `Init/Environment.hs` lines 146-151).

### Where Each Solver Is Called

**Builder.Solver consumers (2 files):**
- `packages/canopy-builder/src/Builder.hs` -- imports `SolverError` type only (line 98)
- `test/Unit/Builder/SolverTest.hs` -- tests the toy solver
- `test/Integration/PureBuilderIntegrationTest.hs` -- tests through Builder

**Deps.Solver consumers (8 production files):**
- `packages/canopy-terminal/src/Install.hs` (line 147) -- `Solver.initEnv`
- `packages/canopy-terminal/src/Install/AppPlan.hs` (line 211) -- `Solver.addToApp`
- `packages/canopy-terminal/src/Install/PkgPlan.hs` (line 193) -- `Solver.verify`
- `packages/canopy-terminal/src/Install/Types.hs` (line 85) -- type imports
- `packages/canopy-terminal/src/Init.hs` (line 68) -- `Solver.initEnv`
- `packages/canopy-terminal/src/Init/Environment.hs` (line 138) -- `Solver.verify`
- `packages/canopy-terminal/src/Init/Project.hs` (line 76) -- type imports

### The Constraint System

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Canopy/Constraint.hs` (246 lines)

The project already has a well-implemented constraint type used by `Deps.Solver`:

```haskell
data Constraint
  = Range Version.Version Op Op Version.Version

data Op = Less | LessOrEqual
```

This supports `1.0.0 <= v < 2.0.0` style Elm constraints. The `satisfies`, `intersect`, and `check` functions are correct. The `Builder.Solver` module defines its own incompatible `Constraint` type (lines 45-51) that duplicates this functionality.

### The Registry System

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Deps/Registry.hs`

The registry already provides the infrastructure needed for real resolution:

```haskell
data Registry = Registry !Int !(Map Pkg.Name (Map Version.Version ()))
data KnownVersions = KnownVersions !Version.Version ![Version.Version]

getVersions' :: CanopyRegistries -> Pkg.Name -> Maybe KnownVersions
```

However, the registry stores only version numbers per package, not each version's dependency map. Real resolution requires fetching `canopy.json` (or equivalent metadata) for each candidate version to discover its dependencies.

## Proposed Solution

### Phase 1: Unify Solver Types

#### Step 1.1: Remove Builder.Solver's Constraint Type

The `Builder.Solver.Constraint` type (`ExactVersion | MinVersion | MaxVersion | RangeVersion | AnyVersion`) is a less precise version of `Canopy.Constraint.Constraint` (`Range Version Op Op Version`). All uses of `Builder.Solver.Constraint` should be replaced with `Canopy.Constraint.Constraint`.

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Builder/Solver.hs`

Remove lines 44-51 (`Constraint` type) and lines 99-104 (`selectVersion`, `combineConstraints`, `mergeConstraints` that operate on the old `Constraint`). Replace with:

```haskell
import qualified Canopy.Constraint as Constraint

-- | Select a version satisfying a constraint from registry versions.
selectVersion ::
  Registry.CanopyRegistries ->
  Pkg.Name ->
  Constraint.Constraint ->
  Maybe Version.Version
selectVersion registry pkg constraint = do
  Registry.KnownVersions latest older <- Registry.getVersions' registry pkg
  findSatisfying constraint (latest : older)

findSatisfying :: Constraint.Constraint -> [Version.Version] -> Maybe Version.Version
findSatisfying constraint = listToMaybe . filter (Constraint.satisfies constraint)
```

#### Step 1.2: Simplify SolverResult

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Deps/Solver.hs`

Replace the 6-constructor `SolverResult` with a 3-constructor version:

```haskell
-- | Solver result.
data SolverResult a
  = SolverOk !a
  | SolverNoSolution ![Pkg.Name]
  | SolverErr !SolverError
  deriving (Show, Eq)

-- | Structured solver error.
data SolverError
  = ConflictingConstraints !Pkg.Name !Constraint.Constraint !Constraint.Constraint
  | PackageNotFound !Pkg.Name
  | VersionNotFound !Pkg.Name !Constraint.Constraint
  | CyclicDependencies ![Pkg.Name]
  | RegistryError !String
  deriving (Show, Eq)
```

Update all 8 consumer files to handle the simplified result type.

### Phase 2: Add Transitive Resolution to Deps.Solver

This is the core improvement. The solver must:

1. For each direct dependency, resolve it to a concrete version
2. Fetch that version's dependencies (from registry metadata or cached `canopy.json`)
3. Add those transitive dependencies to the constraint set
4. Repeat until all dependencies are resolved or a conflict is found
5. On conflict, backtrack and try a different version

#### Step 2.1: Add Package Metadata Fetching

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Deps/Solver.hs`

The solver needs access to each package version's dependency map. Two approaches:

**Approach A: Use cached package metadata**

Each installed package has a `canopy.json` in the package cache (`~/.canopy/packages/<author>/<project>/<version>/canopy.json`). The solver can read these:

```haskell
-- | Fetch the dependency constraints for a specific package version.
--
-- Reads the package's canopy.json from the package cache to discover
-- what other packages (and at what constraint ranges) this version
-- requires.
fetchPackageDeps ::
  Stuff.PackageCache ->
  Pkg.Name ->
  Version.Version ->
  IO (Maybe (Map Pkg.Name Constraint.Constraint))
fetchPackageDeps cache pkg version = do
  let pkgDir = Stuff.package cache pkg version
      outlinePath = pkgDir </> "canopy.json"
  exists <- Dir.doesFileExist outlinePath
  if exists
    then readOutlineDeps outlinePath
    else pure Nothing

readOutlineDeps :: FilePath -> IO (Maybe (Map Pkg.Name Constraint.Constraint))
readOutlineDeps path = do
  bytes <- BS.readFile path
  pure $ either (const Nothing) extractDeps (Outline.decode bytes)
  where
    extractDeps (Outline.Pkg (Outline.PkgOutline _ _ _ _ _ deps _ _)) = Just deps
    extractDeps (Outline.App _) = Nothing
```

**Approach B: Extend the registry with dependency metadata**

Add dependency data to `Registry` so it does not require per-version file I/O:

```haskell
data PackageVersionInfo = PackageVersionInfo
  { _pviDeps :: !(Map Pkg.Name Constraint.Constraint)
  }

-- Extended registry with dependency metadata
data ExtendedRegistry = ExtendedRegistry
  { _erVersions :: !(Map Pkg.Name (Map Version.Version PackageVersionInfo))
  }
```

**Recommendation:** Approach A is simpler and leverages existing infrastructure. Package metadata is already cached by `canopy install`. Approach B is more efficient but requires registry format changes.

#### Step 2.2: Implement Recursive Resolution with Backtracking

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Deps/Solver.hs`

Replace `resolveConstraints` with a real solver:

```haskell
-- | Solver state tracking resolved versions and accumulated constraints.
data SolverState = SolverState
  { _ssResolved :: !(Map Pkg.Name Version.Version)
  , _ssConstraints :: !(Map Pkg.Name Constraint.Constraint)
  , _ssVisited :: !(Set Pkg.Name)
  }

-- | Resolve all dependencies transitively.
--
-- Starting from the direct dependencies, recursively resolves each
-- package's transitive dependencies. Uses backtracking when version
-- conflicts are detected: if a chosen version's dependencies conflict
-- with existing constraints, the solver tries the next lower version.
resolveAll ::
  Stuff.PackageCache ->
  Registry.CanopyRegistries ->
  Map Pkg.Name Constraint.Constraint ->
  IO (SolverResult (Map Pkg.Name Details))
resolveAll cache registry directDeps =
  runSolver cache registry initialState (Map.toList directDeps)
  where
    initialState = SolverState Map.empty directDeps Set.empty

-- | Core solver loop with backtracking.
runSolver ::
  Stuff.PackageCache ->
  Registry.CanopyRegistries ->
  SolverState ->
  [(Pkg.Name, Constraint.Constraint)] ->
  IO (SolverResult (Map Pkg.Name Details))
runSolver _cache _registry state [] =
  pure (SolverOk (Map.map (\v -> Details v Map.empty) (_ssResolved state)))
runSolver cache registry state ((pkg, constraint) : rest)
  | Set.member pkg (_ssVisited state) =
      pure (SolverErr (CyclicDependencies [pkg]))
  | Map.member pkg (_ssResolved state) =
      -- Already resolved; check compatibility
      checkExistingResolution cache registry state pkg constraint rest
  | otherwise =
      tryVersions cache registry state pkg constraint rest candidates
  where
    candidates = getCandidateVersions registry pkg constraint

-- | Try candidate versions in descending order.
--
-- For each candidate version, fetches its transitive dependencies,
-- checks for constraint conflicts, and recurses. If the version
-- fails, tries the next candidate (backtracking).
tryVersions ::
  Stuff.PackageCache ->
  Registry.CanopyRegistries ->
  SolverState ->
  Pkg.Name ->
  Constraint.Constraint ->
  [(Pkg.Name, Constraint.Constraint)] ->
  [Version.Version] ->
  IO (SolverResult (Map Pkg.Name Details))
tryVersions _cache _registry _state pkg _constraint _rest [] =
  pure (SolverNoSolution [pkg])
tryVersions cache registry state pkg constraint rest (v : vs) = do
  transDeps <- fetchPackageDeps cache pkg v
  let newState = state
        { _ssResolved = Map.insert pkg v (_ssResolved state)
        , _ssVisited = Set.insert pkg (_ssVisited state)
        }
      transConstraints = maybe [] Map.toList transDeps
  result <- runSolver cache registry newState (transConstraints ++ rest)
  handleBacktrack result cache registry state pkg constraint rest vs

handleBacktrack (SolverOk solution) _ _ _ _ _ _ _ = pure (SolverOk solution)
handleBacktrack (SolverNoSolution _) cache registry state pkg constraint rest vs =
  tryVersions cache registry state pkg constraint rest vs  -- Backtrack
handleBacktrack err _ _ _ _ _ _ _ = pure err  -- Propagate errors
```

#### Step 2.3: Get Candidate Versions from Registry

```haskell
-- | Get all versions of a package satisfying a constraint, in descending order.
--
-- The registry stores versions with the latest first, so filtering
-- preserves the descending order needed for backtracking (try highest first).
getCandidateVersions ::
  Registry.CanopyRegistries ->
  Pkg.Name ->
  Constraint.Constraint ->
  [Version.Version]
getCandidateVersions registry pkg constraint =
  case Registry.getVersions' registry pkg of
    Nothing -> []
    Just (Registry.KnownVersions latest older) ->
      filter (Constraint.satisfies constraint) (latest : older)
```

### Phase 3: Update Consumers

#### Step 3.1: Update verify

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Deps/Solver.hs`

```haskell
verify ::
  Stuff.PackageCache ->
  Connection ->
  Registry.CanopyRegistries ->
  Map Pkg.Name Constraint.Constraint ->
  IO (SolverResult (Map Pkg.Name Details))
verify cache _connection registry constraints =
  resolveAll cache registry constraints
```

#### Step 3.2: Update addToApp

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Deps/Solver.hs`

```haskell
addToApp ::
  Stuff.PackageCache ->
  Connection ->
  Registry.CanopyRegistries ->
  Pkg.Name ->
  Outline.AppOutline ->
  IO (SolverResult AppSolution)
addToApp cache _connection registry newPkg outline =
  case Registry.getVersions' registry newPkg of
    Nothing -> pure (SolverNoSolution [newPkg])
    Just (Registry.KnownVersions latestVersion _) -> do
      -- Verify all existing deps + new pkg can be resolved together
      let existingDeps = constraintsFromApp outline
          newDeps = Map.insert newPkg (Constraint.exactly latestVersion) existingDeps
      result <- resolveAll cache registry newDeps
      pure (fmap (buildAppSolutionFromResolved outline newPkg latestVersion) result)
```

#### Step 3.3: Update Consumer Pattern Matching

All files matching on `Solver.Ok`, `Solver.Online`, `Solver.Offline` must be updated to match on `Solver.SolverOk`:

**Files to update:**
- `packages/canopy-terminal/src/Install/AppPlan.hs` (lines 213-224)
- `packages/canopy-terminal/src/Install/PkgPlan.hs` (lines 194-200)
- `packages/canopy-terminal/src/Init/Environment.hs` (lines 139-151)

### Phase 4: Deprecate Builder.Solver

The `Builder.Solver` module is a toy implementation used only by tests. Since `Builder.hs` only references its `SolverError` type (and the `BuildErrorSolver` constructor is never used in production code), the module can be simplified:

1. Move `SolverError` into `Builder.hs` directly (4 constructors, ~10 lines)
2. Remove `Builder.Solver` module
3. Update `canopy-builder.cabal` to remove the module
4. Update tests to use `Deps.Solver` or remove toy solver tests

Alternatively, keep `Builder.Solver` as a pure in-memory solver for testing scenarios but rewrite it to use `Canopy.Constraint.Constraint` and accept a version map (simulating a registry) instead of hard-coding versions.

## Files to Modify

### Phase 1: Type Unification

| File | Change |
|------|--------|
| `packages/canopy-terminal/src/Deps/Solver.hs` | Simplify `SolverResult` from 6 to 3 constructors; add `SolverError` type |
| `packages/canopy-terminal/src/Install/AppPlan.hs` | Update pattern matching for new `SolverResult` |
| `packages/canopy-terminal/src/Install/PkgPlan.hs` | Update pattern matching for new `SolverResult` |
| `packages/canopy-terminal/src/Init/Environment.hs` | Update pattern matching for new `SolverResult` |
| `packages/canopy-terminal/src/Init/Project.hs` | Update type imports if needed |
| `packages/canopy-terminal/src/Install/Types.hs` | Update type imports if needed |

### Phase 2: Transitive Resolution

| File | Change |
|------|--------|
| `packages/canopy-terminal/src/Deps/Solver.hs` | Replace `resolveConstraints`/`resolveOne` with `resolveAll`/`runSolver`/`tryVersions`; add `fetchPackageDeps`, `getCandidateVersions` |
| `packages/canopy-terminal/src/Deps/Registry.hs` | No changes (existing API sufficient) |

### Phase 3: Consumer Updates

| File | Change |
|------|--------|
| `packages/canopy-terminal/src/Install/AppPlan.hs` | Update `attemptAppSolverAddition` for new result type |
| `packages/canopy-terminal/src/Install/PkgPlan.hs` | Update `solvePkgDependency` for new result type |
| `packages/canopy-terminal/src/Init/Environment.hs` | Update `resolveDefaults` for new result type |
| `packages/canopy-terminal/src/Install.hs` | No changes needed (calls `Solver.initEnv` which is unchanged) |

### Phase 4: Builder.Solver Cleanup

| File | Change |
|------|--------|
| `packages/canopy-builder/src/Builder/Solver.hs` | Either remove entirely or rewrite to use `Canopy.Constraint` and accept mock registry |
| `packages/canopy-builder/src/Builder.hs` | Move `SolverError` type inline or import from new location |
| `packages/canopy-builder/canopy-builder.cabal` | Remove `Builder.Solver` from exposed-modules if deleted |
| `test/Unit/Builder/SolverTest.hs` | Rewrite tests against `Deps.Solver` or remove |
| `test/Integration/PureBuilderIntegrationTest.hs` | Update if it references `Builder.Solver` |

## Verification

```bash
# 1. All code compiles
make build

# 2. All tests pass
make test

# 3. Verify transitive resolution works
# Create a test project that depends on a package with transitive deps
mkdir -p /tmp/solver-test/src
cat > /tmp/solver-test/canopy.json << 'EOF'
{
  "type": "application",
  "source-directories": ["src"],
  "canopy-version": "0.19.1 <= v < 0.20.0",
  "dependencies": {
    "direct": {
      "elm/core": "1.0.5",
      "elm/html": "1.0.0"
    },
    "indirect": {}
  },
  "test-dependencies": {
    "direct": {},
    "indirect": {}
  }
}
EOF
cat > /tmp/solver-test/src/Main.can << 'EOF'
module Main exposing (..)
import Html
main = Html.text "hello"
EOF
cd /tmp/solver-test && canopy install elm/http
# Should resolve elm/http AND its transitive deps (elm/json, elm/bytes, etc.)
# Indirect deps should appear in canopy.json under "indirect"

# 4. Verify conflict detection
# If two packages require incompatible versions of a shared dep,
# the solver should report a clear error instead of silently picking one

# 5. Verify no remaining hard-coded versions
grep -rn "Version.one" packages/canopy-builder/src/Builder/Solver.hs
# Should return 0 matches (pickVersion removed or rewritten)

# 6. Verify SolverResult simplification
grep -rn "Solver.Online\|Solver.Offline\|Solver.Ok" packages/canopy-terminal/src/
# Should return 0 matches (all replaced with SolverOk)

# 7. Run solver-specific tests
stack test --ta="--pattern Solver"
```

## Notes

### Why Two Solvers Exist

The project has two solver modules because of the package split:
- `canopy-builder` is a pure library that should not depend on `canopy-terminal` or network I/O
- `canopy-terminal` is the CLI that can do network I/O to fetch registries

`Builder.Solver` was intended as a pure dependency solver for the build system, but the build system (`Builder.hs`) does not actually perform dependency resolution -- it receives pre-resolved dependencies from the terminal layer. The `BuildErrorSolver` constructor exists for completeness but is never constructed.

### Comparison with Elm's Solver

Elm's original solver (`Deps.Solver` in the `elm` compiler) uses STM-based parallelism with real transitive resolution. Canopy replaced this with a simpler non-STM version during the fork, but lost the transitive resolution capability. This plan restores that capability without STM.

### Performance Considerations

The backtracking solver's worst case is exponential in the number of packages (standard for SAT-like problems). In practice:

1. Most packages have few versions (< 20), limiting branching
2. The version-descending order means the first attempt usually succeeds
3. The Canopy ecosystem is small, so constraint graphs are shallow
4. Caching package metadata in memory after first fetch avoids repeated I/O

For the foreseeable future, a simple backtracking solver is sufficient. If the ecosystem grows significantly, consider a more sophisticated algorithm (e.g., DPLL-based solver, PubGrub).

### Offline Mode

The current `SolverResult` has `Offline` and `NoOfflineSolution` constructors for offline mode (when network is unavailable). With the simplified result type, offline mode should be handled by the registry layer: if the registry cannot be fetched, use the cached version. The solver itself should not need to distinguish online vs offline -- it operates on whatever registry data is available.
