{-# LANGUAGE OverloadedStrings #-}

-- | Application dependency planning for install operations.
--
-- This module handles dependency planning specifically for Canopy applications
-- (as opposed to packages). Applications have different dependency structures
-- with direct, indirect, test-direct, and test-indirect categories.
--
-- == Key Features
--
-- * Dependency promotion between categories
-- * Existing dependency detection and analysis
-- * Solver integration for new dependency resolution
-- * Application-specific constraint handling
--
-- == Dependency Categories
--
-- Applications organize dependencies into:
--
-- * __Direct__: Primary runtime dependencies
-- * __Indirect__: Transitive dependencies resolved by solver
-- * __Test Direct__: Dependencies used only in test code
-- * __Test Indirect__: Transitive test dependencies
--
-- @since 0.19.1
module Install.AppPlan
  ( -- * Plan Creation
    makeAppPlan,

    -- * Dependency Analysis
    findExistingAppDependency,
    isAlreadyDirectApp,

    -- * Promotion Operations
    promoteIndirectDep,
    promoteTestDirectDep,
    promoteTestIndirectDep,

    -- * Solver Integration
    addNewAppDependency,
    attemptAppSolverAddition,
  )
where

import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.Map.Strict as Map
import qualified Deps.Registry as Registry
import qualified Deps.Solver as Solver
import Install.Changes (detectChanges)
import Install.Types
  ( Changes (..),
    ExistingDep (..),
    Task,
  )
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff

-- | Create an installation plan for an application.
--
-- Analyzes the current application outline and determines what changes
-- are needed to install the requested package. Returns different change
-- types based on the current state.
--
-- The planning process:
--
-- 1. Check if package is already directly installed
-- 2. Search for existing dependency in other categories
-- 3. Create promotion plan if found, or new dependency plan if not
--
-- ==== Examples
--
-- >>> makeAppPlan env "elm/http" appOutline
-- Right (PromoteIndirect newOutline)  -- if found in indirect deps
--
-- >>> makeAppPlan env "new/package" appOutline
-- Right (Changes changeMap newOutline)  -- if completely new
--
-- @since 0.19.1
makeAppPlan :: Solver.Env -> Pkg.Name -> Outline.AppOutline -> Task (Changes Version.Version)
makeAppPlan env pkg outline =
  if isAlreadyDirectApp pkg outline
    then return AlreadyInstalled
    else checkExistingAppDependencies env pkg outline

-- | Check if a package is already a direct dependency.
--
-- Applications should not reinstall packages that are already
-- in their direct dependency list.
--
-- @since 0.19.1
isAlreadyDirectApp :: Pkg.Name -> Outline.AppOutline -> Bool
isAlreadyDirectApp pkg (Outline.AppOutline {Outline._appDepsDirect = direct}) =
  Map.member pkg direct

-- | Check for existing dependencies that can be promoted.
--
-- Searches all dependency categories to see if the package
-- already exists and can be promoted to direct dependencies.
--
-- @since 0.19.1
checkExistingAppDependencies :: Solver.Env -> Pkg.Name -> Outline.AppOutline -> Task (Changes Version.Version)
checkExistingAppDependencies env pkg outline =
  case findExistingAppDependency pkg outline of
    Just (IndirectDep vsn) -> return $ promoteIndirectDep pkg vsn outline
    Just (TestDirectDep vsn) -> return $ promoteTestDirectDep pkg vsn outline
    Just (TestIndirectDep vsn) -> return $ promoteTestIndirectDep pkg vsn outline -- Legacy case for compatibility
    Nothing -> addNewAppDependency env pkg outline

-- | Find an existing dependency in any category.
--
-- Searches through indirect and test-direct dependencies to locate the package.
-- Note: The NEW AppOutline structure does not have test-indirect dependencies.
--
-- @since 0.19.1
findExistingAppDependency :: Pkg.Name -> Outline.AppOutline -> Maybe ExistingDep
findExistingAppDependency pkg (Outline.AppOutline {Outline._appDepsIndirect = indirect, Outline._appTestDepsDirect = testDirect}) =
  case Map.lookup pkg indirect of
    Just vsn -> Just (IndirectDep vsn)
    Nothing -> case Map.lookup pkg testDirect of
      Just vsn -> Just (TestDirectDep vsn)
      Nothing -> Nothing

-- | Promote a package from indirect to direct dependencies.
--
-- Creates a plan to move a package that was resolved as an indirect
-- dependency into the direct dependency category.
--
-- @since 0.19.1
promoteIndirectDep :: Pkg.Name -> Version.Version -> Outline.AppOutline -> Changes Version.Version
promoteIndirectDep pkg vsn outline =
  PromoteIndirect . Outline.App $
    outline
      { Outline._appDepsDirect = Map.insert pkg vsn (Outline._appDepsDirect outline),
        Outline._appDepsIndirect = Map.delete pkg (Outline._appDepsIndirect outline)
      }

-- | Promote a package from test-direct to direct dependencies.
--
-- Creates a plan to move a package from test dependencies to
-- main dependencies for general use.
--
-- @since 0.19.1
promoteTestDirectDep :: Pkg.Name -> Version.Version -> Outline.AppOutline -> Changes Version.Version
promoteTestDirectDep pkg vsn outline =
  PromoteTest . Outline.App $
    outline
      { Outline._appDepsDirect = Map.insert pkg vsn (Outline._appDepsDirect outline),
        Outline._appTestDepsDirect = Map.delete pkg (Outline._appTestDepsDirect outline)
      }

-- | Promote a package from test-indirect to direct dependencies.
--
-- Creates a plan to move a package from test indirect dependencies
-- to main direct dependencies. Note: The NEW AppOutline structure does
-- not have test-indirect, so this is a legacy function that won't be called.
--
-- @since 0.19.1
promoteTestIndirectDep :: Pkg.Name -> Version.Version -> Outline.AppOutline -> Changes Version.Version
promoteTestIndirectDep pkg vsn outline =
  PromoteTest . Outline.App $
    outline
      { Outline._appDepsDirect = Map.insert pkg vsn (Outline._appDepsDirect outline)
        -- No test-indirect field to delete from in NEW structure
      }

-- | Add a completely new dependency to the application.
--
-- Uses the solver to resolve dependencies for a package that
-- doesn't exist anywhere in the current dependency structure.
--
-- @since 0.19.1
addNewAppDependency :: Solver.Env -> Pkg.Name -> Outline.AppOutline -> Task (Changes Version.Version)
addNewAppDependency env pkg outline =
  case extractSolverComponents env of
    (cache, connection, registry) ->
      case Registry.getVersions' registry pkg of
        Nothing -> throwAppUnknownPackageError connection pkg []
        Just _ -> attemptAppSolverAddition cache connection registry pkg outline

-- | Extract solver environment components.
--
-- Unpacks the solver environment into its constituent parts
-- for use in dependency resolution operations.
--
-- @since 0.19.1
extractSolverComponents :: Solver.Env -> (Stuff.PackageCache, Solver.Connection, Registry.CanopyRegistries)
extractSolverComponents (Solver.Env cache _ connection registry _) =
  (cache, connection, registry)

-- | Throw an error for unknown packages in app context.
--
-- Provides appropriate error messages with suggestions when
-- a requested package cannot be found in the registry.
--
-- @since 0.19.1
throwAppUnknownPackageError :: Solver.Connection -> Pkg.Name -> [Pkg.Name] -> Task (Changes Version.Version)
throwAppUnknownPackageError _connection pkg suggestions =
  Task.throw (Exit.InstallUnknownPackageOnline (Pkg.toChars pkg) (map Pkg.toChars suggestions))

-- | Attempt to add a new dependency using the solver.
--
-- Runs the solver to determine what changes are needed to add
-- the new package while maintaining dependency consistency.
--
-- @since 0.19.1
attemptAppSolverAddition :: Stuff.PackageCache -> Solver.Connection -> Registry.CanopyRegistries -> Pkg.Name -> Outline.AppOutline -> Task (Changes Version.Version)
attemptAppSolverAddition cache connection registry pkg outline = do
  result <- Task.io $ Solver.addToApp cache connection registry pkg outline
  case result of
    Solver.SolverOk solution ->
      return (Changes (detectChanges (Solver.appSolutionOld solution) (Solver.appSolutionNew solution)) (Outline.App (Solver.appSolutionOutline solution)))
    Solver.SolverNoSolution _ ->
      Task.throw (Exit.InstallNoOnlineAppSolution (Pkg.toChars pkg))
    Solver.SolverErr exit ->
      Task.throw (Exit.InstallHadSolverTrouble exit)
