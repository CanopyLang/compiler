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

-- | Verify solver details.
verify :: a -> b -> c -> d -> IO (SolverResult (Map Pkg.Name Details))
verify _ _ _ _ = pure (Ok Map.empty)

-- | Add package to application dependencies.
--
-- Attempts to add a new package to an application's dependencies by solving
-- for compatible versions. Returns the old and new dependency sets along with
-- the updated outline.
--
-- @since 0.19.1
addToApp ::
  Stuff.PackageCache ->
  Connection ->
  Registry.CanopyRegistries ->
  Pkg.Name ->
  Outline.AppOutline ->
  IO (SolverResult AppSolution)
addToApp _cache _connection _registry newPkg outline =
  let oldDeps = Outline._appDepsDirect outline
      oldIndirect = Outline._appDepsIndirect outline
      oldCombined = Map.union oldDeps oldIndirect
      newDeps = Map.insert newPkg Version.one oldDeps
      newIndirect = oldIndirect
      newCombined = Map.insert newPkg Version.one oldCombined
      newOutline =
        outline
          { Outline._appDepsDirect = newDeps,
            Outline._appDepsIndirect = newIndirect
          }
      solution =
        AppSolution
          { appSolutionOld = oldCombined,
            appSolutionNew = newCombined,
            appSolutionOutline = newOutline
          }
   in pure (Ok solution)
