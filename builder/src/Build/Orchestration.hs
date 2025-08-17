{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Build orchestration coordination for the Canopy compiler.
--
-- This module serves as the main coordination interface for build orchestration,
-- providing clean re-exports from specialized sub-modules and additional
-- validation utilities. It maintains the public API while delegating
-- implementation to focused sub-modules.
--
-- === Architecture Overview
--
-- The build orchestration is organized into focused sub-modules:
--
-- * "Build.Orchestration.Workflow" - Main build workflow coordination
-- * "Build.Orchestration.Repl" - REPL-specific build orchestration
-- * "Build.Orchestration" - Coordination interface and validation utilities
--
-- === Usage Examples
--
-- @
-- -- Main build workflow
-- let config = ExposedBuildConfig style root details goal
-- result <- fromExposed config exposedModules
-- case result of
--   Left problem -> handleBuildError problem
--   Right docs -> processDocs docs
--
-- -- REPL interaction
-- result <- fromRepl root details sourceCode
-- case result of
--   Left replError -> handleReplError replError
--   Right artifacts -> useReplArtifacts artifacts
--
-- -- Environment creation
-- env <- makeEnv key root details
-- let srcDirs = env ^. envSrcDirs
-- @
--
-- === Build Coordination
--
-- This module coordinates between:
--
-- * Main build workflow orchestration
-- * REPL-specific build processing
-- * Project validation and integrity checking
-- * Environment management and path utilities
-- * Threading and concurrency coordination
--
-- @since 0.19.1
module Build.Orchestration
  ( -- * Main Build Functions
    -- | Re-exported from "Build.Orchestration.Workflow"
    fromExposed
  , ExposedBuildConfig (..)
    
  -- * REPL Build Functions  
    -- | Re-exported from "Build.Orchestration.Repl"
  , fromRepl
    
  -- * Environment Management
    -- | Re-exported from "Build.Orchestration.Workflow"
  , makeEnv
  , toAbsoluteSrcDir
  , addRelative
    
  -- * Project Validation
  , checkMidpoint
  , checkMidpointAndRoots
    
  -- * Threading Utilities
    -- | Re-exported from "Build.Orchestration.Workflow"
  , fork
  , forkWithKey
    
  -- * Configuration Lenses
    -- | Re-exported from "Build.Orchestration.Workflow"
  , ebcStyle
  , ebcRoot
  , ebcDetails
  , ebcDocsGoal
  ) where

-- Re-exports from specialized sub-modules
import Build.Orchestration.Workflow
  ( fromExposed
  , ExposedBuildConfig (..)
  , makeEnv
  , toAbsoluteSrcDir
  , addRelative
  , fork
  , forkWithKey
  , ebcStyle
  , ebcRoot
  , ebcDetails
  , ebcDocsGoal
  )
import Build.Orchestration.Repl (fromRepl)

-- Canopy-specific imports for validation
import qualified Canopy.ModuleName as ModuleName

-- Build system imports for validation functions
import Build.Types
  ( Status (..)
  , Dependencies
  , RootStatus (..)
  )
import qualified Build.Validation as Validation

-- Standard library imports
import Control.Concurrent.MVar (MVar, readMVar)
import Data.Map.Strict (Map)
import qualified Data.NonEmptyList as NE
import qualified Reporting.Exit as Exit

-- =============================================================================
-- Project Validation Functions  
-- =============================================================================
-- These functions remain in the coordinating module as they are used by 
-- both workflow and REPL orchestration.

-- | Check project integrity at the midpoint of the build.
--
-- Validates that all dependencies are available and no cyclic dependencies
-- exist. This is called after module crawling but before compilation.
--
-- Used by both main build workflow and REPL compilation to ensure
-- project integrity before proceeding with module compilation.
--
-- ==== Validation Process
--
-- 1. Check for cyclic dependencies in the module graph
-- 2. Verify that all foreign dependencies are available
-- 3. Ensure interfaces can be loaded successfully
--
-- @since 0.19.1
checkMidpoint :: MVar (Maybe Dependencies) -> Map ModuleName.Raw Status -> IO (Either Exit.BuildProjectProblem Dependencies)
checkMidpoint dmvar statuses =
  case Validation.checkForCycles statuses of
    Nothing -> do
      maybeForeigns <- readMVar dmvar
      case maybeForeigns of
        Nothing -> return (Left Exit.BP_CannotLoadDependencies)
        Just fs -> return (Right fs)
    Just (NE.List name names) -> do
      _ <- readMVar dmvar
      return (Left (Exit.BP_Cycle name names))

-- | Check project integrity including root validation.
--
-- Extended midpoint check that also validates root modules are unique
-- and properly structured. Used when building from file paths rather
-- than module names.
--
-- This function provides additional validation beyond 'checkMidpoint'
-- by ensuring that root modules don't conflict and follow proper
-- naming conventions.
--
-- ==== Extended Validation
--
-- 1. All checks from 'checkMidpoint'
-- 2. Root module uniqueness validation
-- 3. Root module name consistency checks
-- 4. File path to module name mapping validation
--
-- @since 0.19.1
checkMidpointAndRoots :: MVar (Maybe Dependencies) -> Map ModuleName.Raw Status -> NE.List RootStatus -> IO (Either Exit.BuildProjectProblem Dependencies)
checkMidpointAndRoots dmvar statuses sroots =
  case Validation.checkForCycles statuses of
    Nothing ->
      case Validation.checkUniqueRoots statuses sroots of
        Nothing -> do
          maybeForeigns <- readMVar dmvar
          case maybeForeigns of
            Nothing -> return (Left Exit.BP_CannotLoadDependencies)
            Just fs -> return (Right fs)
        Just problem -> do
          _ <- readMVar dmvar
          return (Left problem)
    Just (NE.List name names) -> do
      _ <- readMVar dmvar
      return (Left (Exit.BP_Cycle name names))