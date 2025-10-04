{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Dependency solver stub for Terminal.
--
-- Minimal stub for dependency resolution. The OLD module handled
-- complex constraint solving for package dependencies.
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
import qualified Canopy.Version as V
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Deps.Registry as Registry
import qualified Http
import qualified Stuff

-- | Connection type for solver (stub).
type Connection = ()

-- | App solution with old and new dependency maps.
data AppSolution = AppSolution
  { appSolutionOld :: !(Map Pkg.Name V.Version)
  , appSolutionNew :: !(Map Pkg.Name V.Version)
  , appSolutionOutline :: !Outline.AppOutline
  }
  deriving (Show)

-- | Solver environment.
data Env = Env !Stuff.PackageCache !Http.Manager !Connection !Registry.CanopyRegistries !(Map Pkg.Name V.Version)

-- | Package details with version and direct dependencies.
data Details = Details !V.Version !(Map Pkg.Name V.Version)
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

-- | Initialize solver environment (stub).
initEnv :: IO (Either String Env)
initEnv = do
  cache <- Stuff.getPackageCache
  manager <- Http.getManager
  let connection = ()
  let emptyRegistry = Registry.Registry 0 Map.empty
  let registries = Registry.CanopyRegistries emptyRegistry [] Map.empty
  pure (Right (Env cache manager connection registries Map.empty))

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
      newDeps = Map.insert newPkg V.one oldDeps
      newIndirect = oldIndirect
      newCombined = Map.insert newPkg V.one oldCombined
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
