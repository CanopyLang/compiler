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
    PkgSolverContext (..),
    addNewPkgDependency,
    solvePkgDependency,
    buildPkgSolution,
    
    -- * Utilities
    addNewsToPackage,
  ) where

import qualified Canopy.Constraint as Constraint
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
makePkgPlan :: Solver.Env -> Pkg.Name -> Outline.PkgOutline -> Task (Changes Constraint.Constraint)
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
checkPkgTestDependencies :: Solver.Env -> Pkg.Name -> Outline.PkgOutline -> Task (Changes Constraint.Constraint)
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
promotePkgTestDep :: Pkg.Name -> Constraint.Constraint -> Outline.PkgOutline -> Changes Constraint.Constraint
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
addNewPkgDependency :: Solver.Env -> Pkg.Name -> Outline.PkgOutline -> Task (Changes Constraint.Constraint)
addNewPkgDependency env pkg outline = do
  let solverCtx = extractPkgSolverComponents env
      PkgSolverContext _cache connection registry = solverCtx
  case Registry.getVersions' pkg registry of
    Left suggestions -> throwPkgUnknownPackageError connection pkg suggestions
    Right _ -> solvePkgDependency solverCtx pkg outline

-- | Package solver context containing all needed components.
--
-- Groups solver components together to avoid parameter list violations
-- while maintaining clear component access.
--
-- @since 0.19.1
data PkgSolverContext = PkgSolverContext
  { _pscCache :: !Stuff.PackageCache
  , _pscConnection :: !Solver.Connection
  , _pscRegistry :: !Registry.ZokkaRegistries
  }

-- | Extract solver environment components for package operations.
--
-- Unpacks the solver environment into a structured context for
-- package-specific dependency resolution operations.
--
-- @since 0.19.1
extractPkgSolverComponents :: Solver.Env -> PkgSolverContext
extractPkgSolverComponents (Solver.Env cache _ connection registry _) =
  PkgSolverContext cache connection registry

-- | Throw an error for unknown packages in package context.
--
-- Provides appropriate error messages with suggestions when
-- a requested dependency cannot be found in the registry.
--
-- @since 0.19.1
throwPkgUnknownPackageError :: Solver.Connection -> Pkg.Name -> [Pkg.Name] -> Task (Changes Constraint.Constraint)
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
solvePkgDependency :: PkgSolverContext -> Pkg.Name -> Outline.PkgOutline -> Task (Changes Constraint.Constraint)
solvePkgDependency solverCtx pkg outline = do
  let PkgSolverContext cache connection registry = solverCtx
  case outline of
    Outline.PkgOutline _ _ _ _ _ deps testDeps _ -> do
      let oldConstraints = Map.union deps testDeps
          newConstraints = Map.insert pkg Constraint.anything oldConstraints
      
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
buildPkgSolution :: Pkg.Name -> Map Pkg.Name Solver.Details -> Map Pkg.Name Constraint.Constraint -> Outline.PkgOutline -> Changes Constraint.Constraint
buildPkgSolution pkg solution oldConstraints outline =
  case outline of
    Outline.PkgOutline n summary license version exposed deps testDeps srcDirs ->
      let (Solver.Details vsn _) = solution ! pkg
          constraint = Constraint.untilNextMajor vsn
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
addNewsToPackage :: Maybe Pkg.Name -> Map Pkg.Name Constraint.Constraint -> Map Pkg.Name Constraint.Constraint -> Map Pkg.Name Constraint.Constraint
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
includeIfTarget :: Maybe Pkg.Name -> Pkg.Name -> Constraint.Constraint -> Maybe Constraint.Constraint
includeIfTarget targetPkg pkgName constraint =
  if Just pkgName == targetPkg
    then Just constraint
    else Nothing