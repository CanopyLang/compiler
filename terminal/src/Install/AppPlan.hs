{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

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
  ) where

import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.Map as Map
import qualified Deps.Registry as Registry
import qualified Deps.Solver as Solver
import Install.Changes (detectChanges)
import Install.Types 
  ( Changes (..)
  , ExistingDep (..)
  , Task
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
isAlreadyDirectApp pkg outline =
  case outline of
    Outline.AppOutline _ _ direct _ _ _ _ -> Map.member pkg direct

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
    Just (TestIndirectDep vsn) -> return $ promoteTestIndirectDep pkg vsn outline
    Nothing -> addNewAppDependency env pkg outline

-- | Find an existing dependency in any category.
--
-- Searches through indirect, test-direct, and test-indirect
-- dependencies to locate the package.
--
-- @since 0.19.1
findExistingAppDependency :: Pkg.Name -> Outline.AppOutline -> Maybe ExistingDep
findExistingAppDependency pkg outline =
  case outline of
    Outline.AppOutline _ _ _ indirect testDirect testIndirect _ ->
      case Map.lookup pkg indirect of
        Just vsn -> Just (IndirectDep vsn)
        Nothing -> case Map.lookup pkg testDirect of
          Just vsn -> Just (TestDirectDep vsn)
          Nothing -> case Map.lookup pkg testIndirect of
            Just vsn -> Just (TestIndirectDep vsn)
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
    case outline of
      Outline.AppOutline name summary direct indirect testDirect testIndirect srcDirs ->
        Outline.AppOutline name summary 
          (Map.insert pkg vsn direct) 
          (Map.delete pkg indirect) 
          testDirect testIndirect srcDirs

-- | Promote a package from test-direct to direct dependencies.
--
-- Creates a plan to move a package from test dependencies to
-- main dependencies for general use.
--
-- @since 0.19.1
promoteTestDirectDep :: Pkg.Name -> Version.Version -> Outline.AppOutline -> Changes Version.Version
promoteTestDirectDep pkg vsn outline =
  PromoteTest . Outline.App $
    case outline of
      Outline.AppOutline name summary direct indirect testDirect testIndirect srcDirs ->
        Outline.AppOutline name summary 
          (Map.insert pkg vsn direct) 
          indirect 
          (Map.delete pkg testDirect) 
          testIndirect srcDirs

-- | Promote a package from test-indirect to direct dependencies.
--
-- Creates a plan to move a package from test indirect dependencies
-- to main direct dependencies.
--
-- @since 0.19.1
promoteTestIndirectDep :: Pkg.Name -> Version.Version -> Outline.AppOutline -> Changes Version.Version
promoteTestIndirectDep pkg vsn outline =
  PromoteTest . Outline.App $
    case outline of
      Outline.AppOutline name summary direct indirect testDirect testIndirect srcDirs ->
        Outline.AppOutline name summary 
          (Map.insert pkg vsn direct) 
          indirect 
          testDirect 
          (Map.delete pkg testIndirect) 
          srcDirs

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
      case Registry.getVersions' pkg registry of
        Left suggestions -> throwAppUnknownPackageError connection pkg suggestions
        Right _ -> attemptAppSolverAddition cache connection registry pkg outline

-- | Extract solver environment components.
--
-- Unpacks the solver environment into its constituent parts
-- for use in dependency resolution operations.
--
-- @since 0.19.1
extractSolverComponents :: Solver.Env -> (Stuff.PackageCache, Solver.Connection, Registry.ZokkaRegistries)
extractSolverComponents (Solver.Env cache _ connection registry _) =
  (cache, connection, registry)

-- | Throw an error for unknown packages in app context.
--
-- Provides appropriate error messages with suggestions when
-- a requested package cannot be found in the registry.
--
-- @since 0.19.1
throwAppUnknownPackageError :: Solver.Connection -> Pkg.Name -> [Pkg.Name] -> Task (Changes Version.Version)
throwAppUnknownPackageError connection pkg suggestions =
  case connection of
    Solver.Online _ -> Task.throw (Exit.InstallUnknownPackageOnline pkg suggestions)
    Solver.Offline _ -> Task.throw (Exit.InstallUnknownPackageOffline pkg suggestions)

-- | Attempt to add a new dependency using the solver.
--
-- Runs the solver to determine what changes are needed to add
-- the new package while maintaining dependency consistency.
--
-- @since 0.19.1
attemptAppSolverAddition :: Stuff.PackageCache -> Solver.Connection -> Registry.ZokkaRegistries -> Pkg.Name -> Outline.AppOutline -> Task (Changes Version.Version)
attemptAppSolverAddition cache connection registry pkg outline = do
  result <- Task.io $ Solver.addToApp cache connection registry pkg outline
  case result of
    Solver.Ok (Solver.AppSolution old new app) ->
      return (Changes (detectChanges old new) (Outline.App app))
    Solver.NoSolution ->
      Task.throw (Exit.InstallNoOnlineAppSolution pkg)
    Solver.NoOfflineSolution _ ->
      Task.throw (Exit.InstallNoOfflineAppSolution pkg)
    Solver.Err exit ->
      Task.throw (Exit.InstallHadSolverTrouble exit)