{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Package dependency planning for install operations.
--
-- This module handles dependency planning specifically for Canopy packages
-- (as opposed to applications). Packages have simpler dependency structures
-- with main dependencies and test dependencies only.
--
-- == Key Features
--
-- * Package-specific constraint handling using semantic versioning
-- * Test dependency promotion to main dependencies
-- * Constraint-based solver integration
-- * Package publishing compatibility
--
-- == Package Dependencies
--
-- Packages organize dependencies into:
--
-- * __Dependencies__: Required for package consumers
-- * __Test Dependencies__: Only needed during package testing
--
-- @since 0.19.1
module Install.PkgPlan
  ( -- * Plan Creation
    makePkgPlan,
    
    -- * Dependency Analysis
    isPkgAlreadyDirect,
    checkPkgTestDependencies,
    
    -- * Promotion Operations
    promotePkgTestDep,
    
    -- * Solver Integration
    addNewPkgDependency,
    solvePkgDependency,
    buildPkgSolution,
    
    -- * Utilities
    addNewsToPackage,
  ) where

import qualified Canopy.Constraint as C
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import Data.Map (Map, (!))
import qualified Data.Map as Map
import qualified Data.Map.Merge.Strict as Map
import qualified Deps.Registry as Registry
import qualified Deps.Solver as Solver
import Install.Changes (detectChanges, keepNew)
import Install.Types (Changes (..), Task)
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff

-- | Create an installation plan for a package.
--
-- Analyzes the current package outline and determines what changes
-- are needed to install the requested dependency. Packages have
-- simpler dependency structures than applications.
--
-- The planning process:
--
-- 1. Check if dependency is already in main dependencies
-- 2. Check if it exists in test dependencies for promotion
-- 3. Create new dependency plan if not found anywhere
--
-- ==== Examples
--
-- >>> makePkgPlan env "elm/test" pkgOutline
-- Right (PromoteTest newOutline)  -- if found in test deps
--
-- >>> makePkgPlan env "elm/http" pkgOutline
-- Right (Changes changeMap newOutline)  -- if completely new
--
-- @since 0.19.1
makePkgPlan :: Solver.Env -> Pkg.Name -> Outline.PkgOutline -> Task (Changes C.Constraint)
makePkgPlan env pkg outline =
  if isPkgAlreadyDirect pkg outline
    then return AlreadyInstalled
    else checkPkgTestDependencies env pkg outline

-- | Check if a package is already a direct dependency.
--
-- Packages should not reinstall dependencies that are already
-- in their main dependency list.
--
-- @since 0.19.1
isPkgAlreadyDirect :: Pkg.Name -> Outline.PkgOutline -> Bool
isPkgAlreadyDirect pkg outline =
  case outline of
    Outline.PkgOutline _ _ _ _ _ deps _ _ -> Map.member pkg deps

-- | Check for existing test dependencies that can be promoted.
--
-- Searches test dependencies to see if the package already exists
-- and can be promoted to main dependencies.
--
-- @since 0.19.1
checkPkgTestDependencies :: Solver.Env -> Pkg.Name -> Outline.PkgOutline -> Task (Changes C.Constraint)
checkPkgTestDependencies env pkg outline =
  case outline of
    Outline.PkgOutline _ _ _ _ _ _ testDeps _ ->
      case Map.lookup pkg testDeps of
        Just constraint -> return $ promotePkgTestDep pkg constraint outline
        Nothing -> addNewPkgDependency env pkg outline

-- | Promote a package from test to main dependencies.
--
-- Creates a plan to move a dependency from test-only to general use.
-- This is common when a test utility becomes useful in main code.
--
-- @since 0.19.1
promotePkgTestDep :: Pkg.Name -> C.Constraint -> Outline.PkgOutline -> Changes C.Constraint
promotePkgTestDep pkg constraint outline =
  PromoteTest . Outline.Pkg $
    case outline of
      Outline.PkgOutline n summary license version exposed deps testDeps srcDirs ->
        Outline.PkgOutline n summary license version exposed 
          (Map.insert pkg constraint deps) 
          (Map.delete pkg testDeps) 
          srcDirs

-- | Add a completely new dependency to the package.
--
-- Uses the solver to resolve constraints for a dependency that
-- doesn't exist anywhere in the current package configuration.
--
-- @since 0.19.1
addNewPkgDependency :: Solver.Env -> Pkg.Name -> Outline.PkgOutline -> Task (Changes C.Constraint)
addNewPkgDependency env pkg outline =
  case extractPkgSolverComponents env of
    (cache, connection, registry) ->
      case Registry.getVersions' pkg registry of
        Left suggestions -> throwPkgUnknownPackageError connection pkg suggestions
        Right _ -> solvePkgDependency cache connection registry pkg outline

-- | Extract solver environment components for package operations.
--
-- Unpacks the solver environment for use in package-specific
-- dependency resolution operations.
--
-- @since 0.19.1
extractPkgSolverComponents :: Solver.Env -> (Stuff.PackageCache, Solver.Connection, Registry.ZokkaRegistries)
extractPkgSolverComponents (Solver.Env cache _ connection registry _) =
  (cache, connection, registry)

-- | Throw an error for unknown packages in package context.
--
-- Provides appropriate error messages with suggestions when
-- a requested dependency cannot be found in the registry.
--
-- @since 0.19.1
throwPkgUnknownPackageError :: Solver.Connection -> Pkg.Name -> [Pkg.Name] -> Task (Changes C.Constraint)
throwPkgUnknownPackageError connection pkg suggestions =
  case connection of
    Solver.Online _ -> Task.throw (Exit.InstallUnknownPackageOnline pkg suggestions)
    Solver.Offline _ -> Task.throw (Exit.InstallUnknownPackageOffline pkg suggestions)

-- | Solve dependency constraints for a new package dependency.
--
-- Runs constraint solving to determine what changes are needed
-- to add the new dependency while maintaining version compatibility.
--
-- @since 0.19.1
solvePkgDependency :: Stuff.PackageCache -> Solver.Connection -> Registry.ZokkaRegistries -> Pkg.Name -> Outline.PkgOutline -> Task (Changes C.Constraint)
solvePkgDependency cache connection registry pkg outline = do
  case outline of
    Outline.PkgOutline _ _ _ _ _ deps testDeps _ -> do
      let oldConstraints = Map.union deps testDeps
          newConstraints = Map.insert pkg C.anything oldConstraints
      
      result <- Task.io $ Solver.verify cache connection registry newConstraints
      case result of
        Solver.Ok solution -> return $ buildPkgSolution pkg solution oldConstraints outline
        Solver.NoSolution -> Task.throw (Exit.InstallNoOnlinePkgSolution pkg)
        Solver.NoOfflineSolution _ -> Task.throw (Exit.InstallNoOfflinePkgSolution pkg)
        Solver.Err exit -> Task.throw (Exit.InstallHadSolverTrouble exit)

-- | Build a package solution from solver results.
--
-- Converts solver output into a structured change plan that shows
-- what modifications need to be made to the package configuration.
--
-- @since 0.19.1
buildPkgSolution :: Pkg.Name -> Map Pkg.Name Solver.Details -> Map Pkg.Name C.Constraint -> Outline.PkgOutline -> Changes C.Constraint
buildPkgSolution pkg solution oldConstraints outline =
  case outline of
    Outline.PkgOutline n summary license version exposed deps testDeps srcDirs ->
      let (Solver.Details vsn _) = solution ! pkg
          constraint = C.untilNextMajor vsn
          newConstraints = Map.insert pkg constraint oldConstraints
          changes = detectChanges oldConstraints newConstraints
          newDependencies = Map.mapMaybe keepNew changes
          updatedDeps = addNewsToPackage (Just pkg) newDependencies deps
          updatedTestDeps = addNewsToPackage Nothing newDependencies testDeps
      in Changes changes . Outline.Pkg $
           Outline.PkgOutline n summary license version exposed 
             updatedDeps updatedTestDeps srcDirs

-- | Add new dependencies to appropriate dependency maps.
--
-- Distributes new dependencies between main and test dependency maps
-- based on whether they're the target package or transitive dependencies.
--
-- @since 0.19.1
addNewsToPackage :: Maybe Pkg.Name -> Map Pkg.Name C.Constraint -> Map Pkg.Name C.Constraint -> Map Pkg.Name C.Constraint
addNewsToPackage targetPkg newDeps oldDeps =
  Map.merge
    Map.preserveMissing
    (Map.mapMaybeMissing (includeIfTarget targetPkg))
    (Map.zipWithMatched (\_ _ new -> new))
    oldDeps
    newDeps

-- | Include a dependency only if it matches the target.
--
-- Helper function to filter dependencies based on whether
-- they're the explicitly requested package or transitive.
--
-- @since 0.19.1
includeIfTarget :: Maybe Pkg.Name -> Pkg.Name -> C.Constraint -> Maybe C.Constraint
includeIfTarget targetPkg pkgName constraint =
  if Just pkgName == targetPkg
    then Just constraint
    else Nothing