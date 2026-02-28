{-# LANGUAGE OverloadedStrings #-}

-- | Dependency solver for Terminal.
--
-- Handles dependency resolution for Canopy packages. Initializes the solver
-- environment by fetching the latest package registry so that dependency
-- queries have real package data to work with.
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
import qualified Deps.Registry as Registry
import qualified Http
import qualified Stuff

-- | Connection type for solver.
type Connection = ()

-- | App solution with old and new dependency maps.
data AppSolution = AppSolution
  { appSolutionOld :: !(Map Pkg.Name Version.Version)
  , appSolutionNew :: !(Map Pkg.Name Version.Version)
  , appSolutionOutline :: !Outline.AppOutline
  }
  deriving (Show)

-- | Solver environment.
data Env = Env !Stuff.PackageCache !Http.Manager !Connection !Registry.CanopyRegistries !(Map Pkg.Name Version.Version)

-- | Package details with version and direct dependencies.
data Details = Details !Version.Version !(Map Pkg.Name Version.Version)
  deriving (Show, Eq)

-- | Solver result.
data SolverResult a
  = Err String
  | NoSolution
  | NoOfflineSolution [Pkg.Name]
  | Ok a
  | Online a
  | Offline a
  deriving (Show, Eq)

-- | Legacy Err type for compatibility.
type Err = String

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
-- For each package in the constraint map, looks up available versions
-- in the registry and selects the highest version that satisfies the
-- constraint. Returns a 'Details' map with resolved versions.
--
-- @since 0.19.2
verify ::
  Stuff.PackageCache ->
  Connection ->
  Registry.CanopyRegistries ->
  Map Pkg.Name Constraint.Constraint ->
  IO (SolverResult (Map Pkg.Name Details))
verify _cache _connection registry constraints =
  case resolveConstraints registry (Map.toList constraints) of
    Just resolved -> pure (Ok resolved)
    Nothing -> pure NoSolution

-- | Resolve each constraint against the registry.
--
-- Returns 'Nothing' if any package is unknown or no version satisfies
-- its constraint.
resolveConstraints ::
  Registry.CanopyRegistries ->
  [(Pkg.Name, Constraint.Constraint)] ->
  Maybe (Map Pkg.Name Details)
resolveConstraints registry = fmap Map.fromList . traverse (resolveOne registry)

-- | Resolve a single package constraint against the registry.
resolveOne ::
  Registry.CanopyRegistries ->
  (Pkg.Name, Constraint.Constraint) ->
  Maybe (Pkg.Name, Details)
resolveOne registry (pkg, constraint) = do
  Registry.KnownVersions latest older <- Registry.getVersions' registry pkg
  version <- findSatisfying constraint (latest : older)
  Just (pkg, Details version Map.empty)

-- | Add package to application dependencies.
--
-- Looks up the latest available version of the requested package in
-- the registry and inserts it into the application's direct dependencies.
-- Returns 'NoSolution' if the package is not found in the registry.
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
  case Registry.getVersions' registry newPkg of
    Nothing -> pure NoSolution
    Just (Registry.KnownVersions latestVersion _) ->
      pure (Ok (buildAppSolution outline newPkg latestVersion))

-- | Build an 'AppSolution' by inserting a package at a given version.
buildAppSolution :: Outline.AppOutline -> Pkg.Name -> Version.Version -> AppSolution
buildAppSolution outline pkg version =
  let oldDeps = Outline._appDepsDirect outline
      oldIndirect = Outline._appDepsIndirect outline
      oldCombined = Map.union oldDeps oldIndirect
      newDeps = Map.insert pkg version oldDeps
      newCombined = Map.insert pkg version oldCombined
      newOutline = outline
        { Outline._appDepsDirect = newDeps
        , Outline._appDepsIndirect = oldIndirect
        }
   in AppSolution oldCombined newCombined newOutline

-- | Find the highest version that satisfies a constraint.
--
-- Versions are expected in descending order (latest first), so the
-- first satisfying version is the highest one.
findSatisfying :: Constraint.Constraint -> [Version.Version] -> Maybe Version.Version
findSatisfying constraint versions =
  case filter (Constraint.satisfies constraint) versions of
    [] -> Nothing
    (v : _) -> Just v
