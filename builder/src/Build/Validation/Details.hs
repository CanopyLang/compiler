{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Build details persistence and exposed module finalization.
--
-- This module provides functionality for persisting build details and
-- finalizing exposed module compilation. It handles the final stages
-- of build processing, including details file updates and documentation
-- generation.
--
-- === Primary Functionality
--
-- * Build details persistence ('writeDetails', 'addNewLocal')
-- * Exposed module finalization ('finalizeExposed')
-- * Error collection and categorization ('addErrors', 'addImportProblems')
--
-- === Build Details Management
--
-- Build details persistence follows these steps:
--
-- 1. **Merge Results**: Combine new compilation results with existing locals
-- 2. **Preserve Metadata**: Keep project outline, build ID, and foreign deps
-- 3. **Atomic Write**: Use atomic file operations to prevent corruption
--
-- === Usage Examples
--
-- @
-- -- Write updated build details
-- writeDetails projectRoot oldDetails compilationResults
--
-- -- Finalize exposed modules
-- result <- finalizeExposed root docsGoal exposedModules results
-- case result of
--   Left problems -> handleBuildErrors problems
--   Right docs -> saveDocs docs
-- @
--
-- === Error Collection Strategy
--
-- Error collection operates on these principles:
--
-- * **Comprehensive Gathering**: Collect all types of build errors
-- * **Import Problem Tracking**: Identify unresolved import issues
-- * **Result Classification**: Categorize results for appropriate handling
-- * **Early Termination**: Stop on first serious error for focused reporting
--
-- === Thread Safety
--
-- Build details operations use atomic file writing and immutable data structures
-- to ensure consistency during concurrent builds.
--
-- @since 0.19.1
module Build.Validation.Details
  ( -- * Build Details Persistence
    writeDetails
  , addNewLocal
    -- * Exposed Module Finalization
  , finalizeExposed
    -- * Error Collection
  , addErrors
  , addImportProblems
  ) where

-- Canopy-specific imports
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName

-- Build system imports
import qualified Build.Module.Compile as ModuleCompile
import Build.Types (Result (..), DocsGoal (..))

-- Standard library imports
import qualified Data.Foldable as Foldable
import qualified Data.Map.Strict as Map
import qualified Data.NonEmptyList as NE
import qualified File
import qualified Reporting.Error as Error
import qualified Reporting.Error.Import as Import
import qualified Reporting.Exit as Exit
import qualified Stuff

-- | Write build details to persistent storage.
--
-- Updates the project details file with new compilation results while
-- preserving existing configuration and dependency information. Uses
-- atomic file operations to prevent corruption during concurrent builds.
--
-- ==== Atomic Update Process
--
-- 1. **Merge Results**: Combine new compilation results with existing locals
-- 2. **Preserve Metadata**: Keep project outline, build ID, and foreign deps
-- 3. **Atomic Write**: Use atomic file operations to prevent corruption
--
-- ==== Details Structure Preservation
--
-- Maintains the complete @Details.Details@ structure:
--
-- * @time@: Build timestamp (preserved)
-- * @outline@: Project outline (preserved)  
-- * @buildID@: Build identifier (preserved)
-- * @locals@: Local modules (updated with new results)
-- * @foreigns@: Foreign dependencies (preserved)
-- * @extras@: Additional metadata (preserved)
--
-- @since 0.19.1
writeDetails :: FilePath -> Details.Details -> Map.Map ModuleName.Raw Result -> IO ()
writeDetails root (Details.Details time outline buildID locals foreigns extras) results =
  File.writeBinary (Stuff.details root) $
    Details.Details time outline buildID (Map.foldrWithKey addNewLocal locals results) foreigns extras

-- | Add new local module to details map.
--
-- Updates the local module information with fresh compilation results.
-- Only successful compilation results update the local module cache to
-- maintain consistency and prevent corruption from failed builds.
--
-- ==== Result Classification
--
-- Different result types are handled as follows:
--
-- * **@RNew@**: Fresh compilation - update local cache
-- * **@RSame@**: Unchanged with validation - update local cache
-- * **@RCached@**: No changes needed - preserve existing cache
-- * **@RNotFound@**: Import error - don't update cache
-- * **@RProblem@**: Compilation error - don't update cache  
-- * **@RBlocked@**: Dependency blocked - don't update cache
-- * **@RForeign@**: External module - don't update local cache
-- * **@RKernel@**: Kernel module - don't update local cache
--
-- @since 0.19.1
addNewLocal :: ModuleName.Raw -> Result -> Map.Map ModuleName.Raw Details.Local -> Map.Map ModuleName.Raw Details.Local
addNewLocal name result locals =
  case result of
    RNew local _ _ _ -> Map.insert name local locals
    RSame local _ _ _ -> Map.insert name local locals
    RCached {} -> locals
    RNotFound _ -> locals
    RProblem _ -> locals
    RBlocked -> locals
    RForeign _ -> locals
    RKernel -> locals

-- | Finalize build results for exposed modules.
--
-- Validates that all exposed modules compiled successfully and collects
-- any import problems or compilation errors for comprehensive reporting.
-- Generates documentation if all modules compiled successfully.
--
-- ==== Finalization Algorithm
--
-- 1. **Check Import Problems**: Verify all exposed modules resolved imports
-- 2. **Collect Compilation Errors**: Gather errors from failed compilations
-- 3. **Generate Documentation**: Create docs if no errors occurred
-- 4. **Return Result**: Either error report or successful documentation
--
-- ==== Error Prioritization
--
-- Import problems are checked first because they indicate fundamental
-- module resolution issues that prevent meaningful compilation error
-- analysis. Compilation errors are collected second for modules that
-- did resolve but failed to compile.
--
-- @since 0.19.1
finalizeExposed :: FilePath -> DocsGoal docs -> NE.List ModuleName.Raw -> Map.Map ModuleName.Raw Result -> IO (Either Exit.BuildProblem docs)
finalizeExposed root docsGoal exposed results =
  case Foldable.foldr (addImportProblems results) [] (NE.toList exposed) of
    p : ps ->
      return . Left $ Exit.BuildProjectProblem (Exit.BP_MissingExposed (NE.List p ps))
    [] ->
      case Map.foldr addErrors [] results of
        [] -> Right <$> ModuleCompile.finalizeDocs docsGoal results
        e : es -> return . Left $ Exit.BuildBadModules root e es

-- | Extract compilation errors from results.
--
-- Collects all compilation errors from a result set for comprehensive
-- error reporting. Filters out successful and non-problematic results
-- to focus on actual compilation failures.
--
-- ==== Error Extraction Rules
--
-- Only @RProblem@ results contribute compilation errors:
--
-- * **@RNew@, @RSame@**: Successful compilation - no errors
-- * **@RCached@**: Cache hit - no new errors  
-- * **@RNotFound@**: Import problem - handled separately
-- * **@RProblem@**: Compilation error - extract for reporting
-- * **@RBlocked@**: Dependency issue - handled separately
-- * **@RForeign@, @RKernel@**: External modules - no local errors
--
-- @since 0.19.1
addErrors :: Result -> [Error.Module] -> [Error.Module]
addErrors result errors =
  case result of
    RNew {} -> errors
    RSame {} -> errors
    RCached {} -> errors
    RNotFound _ -> errors
    RProblem e -> e : errors
    RBlocked -> errors
    RForeign _ -> errors
    RKernel -> errors

-- | Collect import problems from results.
--
-- Identifies modules that failed to resolve during import processing
-- and adds them to the problem list for comprehensive error reporting.
--
-- ==== Import Problem Classification
--
-- Only @RNotFound@ results indicate import problems:
--
-- * **@RNew@, @RSame@**: Successful import resolution - no problems
-- * **@RCached@**: Cache hit - imports already resolved
-- * **@RNotFound@**: Import resolution failure - add to problems
-- * **@RProblem@**: Compilation error after import - not import problem
-- * **@RBlocked@**: Dependency blocked - not direct import problem
-- * **@RForeign@, @RKernel@**: External modules - not import problems
--
-- @since 0.19.1
addImportProblems :: Map.Map ModuleName.Raw Result -> ModuleName.Raw -> [(ModuleName.Raw, Import.Problem)] -> [(ModuleName.Raw, Import.Problem)]
addImportProblems results name problems =
  case results Map.! name of
    RNew {} -> problems
    RSame {} -> problems
    RCached {} -> problems
    RNotFound p -> (name, p) : problems
    RProblem _ -> problems
    RBlocked -> problems
    RForeign _ -> problems
    RKernel -> problems