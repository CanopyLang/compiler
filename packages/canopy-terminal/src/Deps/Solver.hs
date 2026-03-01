{-# LANGUAGE OverloadedStrings #-}

-- | Dependency solver for Terminal.
--
-- Handles dependency resolution for Canopy packages with transitive
-- dependency support and backtracking. Initializes the solver environment
-- by fetching the latest package registry so that dependency queries have
-- real package data to work with.
--
-- The solver resolves each direct dependency to a concrete version, then
-- recursively fetches and resolves that version's own dependencies from
-- cached package metadata. When a version conflict is detected, the solver
-- backtracks and tries the next candidate version.
--
-- @since 0.19.1
module Deps.Solver
  ( -- * Types
    Connection,
    Env (..),
    Details (..),
    Err,
    SolverResult (..),
    AppSolution (..),

    -- * Operations
    initEnv,
    verify,
    addToApp,
  )
where

import qualified Canopy.Constraint as Constraint
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Deps.Registry as Registry
import qualified Http
import qualified Stuff
import System.FilePath ((</>))
import qualified System.Directory as Dir

-- | Connection type for solver.
type Connection = ()

-- | App solution with old and new dependency maps.
data AppSolution = AppSolution
  { appSolutionOld :: !(Map Pkg.Name Version.Version),
    appSolutionNew :: !(Map Pkg.Name Version.Version),
    appSolutionOutline :: !Outline.AppOutline
  }
  deriving (Show)

-- | Solver environment.
data Env = Env !Stuff.PackageCache !Http.Manager !Connection !Registry.CanopyRegistries !(Map Pkg.Name Version.Version)

-- | Package details with version and direct dependencies.
data Details = Details !Version.Version !(Map Pkg.Name Version.Version)
  deriving (Show, Eq)

-- | Result of dependency resolution.
--
-- Simplified from the original 6-constructor type. The online\/offline
-- distinction is now handled by the registry layer (which uses a cached
-- registry when the network is unavailable). The solver operates on
-- whatever registry data is available.
--
-- @since 0.19.2
data SolverResult a
  = -- | Resolution succeeded with the given payload.
    SolverOk !a
  | -- | No compatible version set exists. The package list identifies
    -- which packages could not be resolved.
    SolverNoSolution ![Pkg.Name]
  | -- | An internal error occurred during resolution.
    SolverErr !String
  deriving (Show, Eq)

-- | Legacy Err type for compatibility.
type Err = String

-- | Solver state tracking resolved versions and the set of packages
-- currently being visited (for cycle detection).
data SolverState = SolverState
  { _ssResolved :: !(Map Pkg.Name Version.Version),
    _ssVisiting :: !(Set.Set Pkg.Name)
  }

-- | Initialize the solver environment with the latest package registry.
--
-- Fetches the registry from the network (falling back to the disk cache
-- or an empty registry on failure) so that dependency resolution has
-- real package data available.
initEnv :: IO (Either String Env)
initEnv = do
  cache <- Stuff.getPackageCache
  manager <- Http.getManager
  registryResult <- Registry.latest manager Map.empty cache cache
  let registry = either (const (Registry.Registry 0 Map.empty)) id registryResult
      registries = Registry.CanopyRegistries registry [] Map.empty
  pure (Right (Env cache manager () registries Map.empty))

-- | Verify that all dependency constraints can be satisfied.
--
-- Resolves each package transitively: for every direct dependency, the
-- solver picks the highest satisfying version, fetches that version's
-- own dependencies from the package cache, and recursively resolves
-- them. Backtracking is used when a chosen version's transitive
-- dependencies conflict with existing constraints.
--
-- @since 0.19.2
verify ::
  Stuff.PackageCache ->
  Connection ->
  Registry.CanopyRegistries ->
  Map Pkg.Name Constraint.Constraint ->
  IO (SolverResult (Map Pkg.Name Details))
verify cache _connection registry constraints =
  resolveAll cache registry constraints

-- | Resolve all dependencies transitively.
--
-- Starting from the direct dependencies, recursively resolves each
-- package's transitive dependencies. Uses backtracking when version
-- conflicts are detected.
resolveAll ::
  Stuff.PackageCache ->
  Registry.CanopyRegistries ->
  Map Pkg.Name Constraint.Constraint ->
  IO (SolverResult (Map Pkg.Name Details))
resolveAll cache registry directDeps =
  runSolver cache registry initialState (Map.toList directDeps)
  where
    initialState = SolverState Map.empty Set.empty

-- | Core solver loop with backtracking.
--
-- Processes the work list of (package, constraint) pairs one at a time.
-- For each package, either verifies an existing resolution is compatible
-- or tries candidate versions in descending order.
runSolver ::
  Stuff.PackageCache ->
  Registry.CanopyRegistries ->
  SolverState ->
  [(Pkg.Name, Constraint.Constraint)] ->
  IO (SolverResult (Map Pkg.Name Details))
runSolver _cache _registry state [] =
  pure (SolverOk (buildDetailsMap (_ssResolved state)))
runSolver cache registry state ((pkg, constraint) : rest) =
  resolveNextPackage cache registry state pkg constraint rest

-- | Resolve the next package in the work list.
--
-- Handles three cases: cyclic dependency detection, compatibility check
-- for already-resolved packages, and fresh resolution with backtracking.
resolveNextPackage ::
  Stuff.PackageCache ->
  Registry.CanopyRegistries ->
  SolverState ->
  Pkg.Name ->
  Constraint.Constraint ->
  [(Pkg.Name, Constraint.Constraint)] ->
  IO (SolverResult (Map Pkg.Name Details))
resolveNextPackage cache registry state pkg constraint rest
  | Set.member pkg (_ssVisiting state) =
      pure (SolverErr ("Cyclic dependency detected involving " ++ Pkg.toChars pkg))
  | otherwise =
      maybe
        (tryVersions cache registry state pkg constraint rest candidates)
        (checkExisting cache registry state constraint rest)
        (Map.lookup pkg (_ssResolved state))
  where
    candidates = getCandidateVersions registry pkg constraint

-- | Check whether an already-resolved version is compatible with a new constraint.
--
-- If the existing version satisfies the new constraint, continue solving.
-- Otherwise, report a conflict.
checkExisting ::
  Stuff.PackageCache ->
  Registry.CanopyRegistries ->
  SolverState ->
  Constraint.Constraint ->
  [(Pkg.Name, Constraint.Constraint)] ->
  Version.Version ->
  IO (SolverResult (Map Pkg.Name Details))
checkExisting cache registry state constraint rest existingVersion
  | Constraint.satisfies constraint existingVersion =
      runSolver cache registry state rest
  | otherwise =
      pure (SolverNoSolution [])

-- | Try candidate versions in descending order with backtracking.
--
-- For each candidate version, fetches its transitive dependencies
-- from the package cache, adds them to the work list, and recurses.
-- If resolution fails, backtracks to the next candidate.
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
tryVersions cache registry state pkg _constraint rest (v : vs) = do
  transDeps <- fetchPackageDeps cache pkg v
  let newState =
        state
          { _ssResolved = Map.insert pkg v (_ssResolved state),
            _ssVisiting = Set.insert pkg (_ssVisiting state)
          }
      transConstraints = maybe [] Map.toList transDeps
  result <- runSolver cache registry newState (transConstraints ++ rest)
  handleBacktrack result cache registry state pkg rest vs

-- | Handle backtracking after a resolution attempt.
--
-- On success, propagate the solution. On failure, try the next
-- candidate version (backtrack). On error, propagate the error.
handleBacktrack ::
  SolverResult (Map Pkg.Name Details) ->
  Stuff.PackageCache ->
  Registry.CanopyRegistries ->
  SolverState ->
  Pkg.Name ->
  [(Pkg.Name, Constraint.Constraint)] ->
  [Version.Version] ->
  IO (SolverResult (Map Pkg.Name Details))
handleBacktrack (SolverOk solution) _cache _registry _state _pkg _rest _vs =
  pure (SolverOk solution)
handleBacktrack (SolverNoSolution _) cache registry state pkg rest vs =
  tryVersions cache registry state pkg Constraint.anything rest vs
handleBacktrack err _cache _registry _state _pkg _rest _vs =
  pure err

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
  maybe [] filterVersions (Registry.getVersions' registry pkg)
  where
    filterVersions (Registry.KnownVersions latest older) =
      filter (Constraint.satisfies constraint) (latest : older)

-- | Fetch the dependency constraints for a specific package version.
--
-- Reads the package's canopy.json from the package cache to discover
-- what other packages (and at what constraint ranges) this version
-- requires. Returns 'Nothing' if the package metadata is not cached
-- or cannot be parsed.
fetchPackageDeps ::
  Stuff.PackageCache ->
  Pkg.Name ->
  Version.Version ->
  IO (Maybe (Map Pkg.Name Constraint.Constraint))
fetchPackageDeps cache pkg version = do
  let pkgDir = packageVersionDir cache pkg version
  exists <- Dir.doesDirectoryExist pkgDir
  if not exists
    then pure Nothing
    else readOutlineDeps pkgDir

-- | Read dependency constraints from a package's outline file.
readOutlineDeps :: FilePath -> IO (Maybe (Map Pkg.Name Constraint.Constraint))
readOutlineDeps pkgDir = do
  eitherOutline <- Outline.read pkgDir
  pure (either (const Nothing) extractPkgDeps eitherOutline)

-- | Extract package dependencies from an outline.
--
-- Only package outlines have dependency constraints. Application and
-- workspace outlines return 'Nothing'.
extractPkgDeps :: Outline.Outline -> Maybe (Map Pkg.Name Constraint.Constraint)
extractPkgDeps (Outline.Pkg pkgOutline) = Just (Outline._pkgDeps pkgOutline)
extractPkgDeps (Outline.App _) = Nothing
extractPkgDeps (Outline.Workspace _) = Nothing

-- | Build the directory path for a specific package version in the cache.
packageVersionDir :: Stuff.PackageCache -> Pkg.Name -> Version.Version -> FilePath
packageVersionDir cache pkg version =
  cache </> Pkg.toChars pkg </> Version.toChars version

-- | Build a 'Details' map from resolved versions.
--
-- Each package gets a 'Details' entry with its resolved version and
-- an empty direct-dependency map (the full dependency graph is captured
-- by the resolution process itself).
buildDetailsMap :: Map Pkg.Name Version.Version -> Map Pkg.Name Details
buildDetailsMap = Map.map (\v -> Details v Map.empty)

-- | Add package to application dependencies.
--
-- Looks up the latest available version of the requested package in
-- the registry and inserts it into the application's direct dependencies.
-- Returns 'SolverNoSolution' if the package is not found in the registry.
--
-- @since 0.19.2
addToApp ::
  Stuff.PackageCache ->
  Connection ->
  Registry.CanopyRegistries ->
  Pkg.Name ->
  Outline.AppOutline ->
  IO (SolverResult AppSolution)
addToApp _cache _connection registry newPkg outline =
  maybe
    (pure (SolverNoSolution [newPkg]))
    (pure . SolverOk . buildAppSolution outline newPkg . latestOf)
    (Registry.getVersions' registry newPkg)
  where
    latestOf (Registry.KnownVersions latest _) = latest

-- | Build an 'AppSolution' by inserting a package at a given version.
buildAppSolution :: Outline.AppOutline -> Pkg.Name -> Version.Version -> AppSolution
buildAppSolution outline pkg version =
  AppSolution oldCombined newCombined newOutline
  where
    oldDeps = Outline._appDepsDirect outline
    oldIndirect = Outline._appDepsIndirect outline
    oldCombined = Map.union oldDeps oldIndirect
    newDeps = Map.insert pkg version oldDeps
    newCombined = Map.insert pkg version oldCombined
    newOutline =
      outline
        { Outline._appDepsDirect = newDeps,
          Outline._appDepsIndirect = oldIndirect
        }

