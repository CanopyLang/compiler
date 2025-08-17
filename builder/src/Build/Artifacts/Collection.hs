{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Artifact collection and assembly for the Canopy compiler.
--
-- This module handles the primary artifact assembly process, including the
-- collection of compilation results, segregation of problems from successes,
-- and final packaging into the 'Artifacts' structure. It focuses specifically
-- on the aggregation and organization phases of the build process.
--
-- === Primary Responsibilities
--
-- * Main artifact assembly from compilation results ('toArtifacts')
-- * Problem and success segregation ('gatherProblemsOrMains')
-- * Root result processing and error collection
-- * Project type to package name conversion
-- * Comprehensive error aggregation for reporting
--
-- === Usage Examples
--
-- @
-- -- Assemble artifacts from compilation results
-- artifacts <- toArtifacts env dependencies results rootResults
-- case artifacts of
--   Left problem -> handleBuildProblem problem
--   Right artifacts -> packageArtifacts artifacts
--
-- -- Check for compilation problems
-- case gatherProblemsOrMains results rootResults of
--   Left errors -> reportCompilationErrors errors
--   Right roots -> proceedWithBuild roots
-- @
--
-- === Artifact Assembly Process
--
-- The assembly follows these steps:
--
-- 1. **Problem Segregation**: Identify compilation failures vs successes
-- 2. **Root Collection**: Gather successful root modules
-- 3. **Module Integration**: Combine internal and root modules
-- 4. **Final Packaging**: Create complete 'Artifacts' structure
--
-- === Error Handling
--
-- All compilation errors are collected and reported together to provide
-- comprehensive feedback. The module distinguishes between:
--
-- * Compilation problems (syntax, type errors)
-- * Missing dependencies (import resolution failures) 
-- * Blocked dependencies (circular dependencies)
--
-- @since 0.19.1
module Build.Artifacts.Collection
  ( -- * Artifact Assembly
    toArtifacts
  , gatherProblemsOrMains
    
  -- * Root Result Processing
  , addRootResult
  , processFirstRoot
  , finalizeRootResults
  , processBlockedFirstRoot
    
  -- * Utility Functions
  , addErrors
  , projectTypeToPkg
  ) where

-- Canopy-specific imports
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg

-- Build system imports
import Build.Types
  ( Env (..)
  , Dependencies
  , Result (..)
  , Root (..)
  , RootResult (..)
  , Module
  , Artifacts (..)
  )

-- Parser imports
import qualified Parse.Module as Parse

-- Processing module imports
import qualified Build.Artifacts.Processing as Processing

-- Standard library imports
import qualified Data.Foldable as Foldable
import qualified Data.Map.Strict as Map
import qualified Data.NonEmptyList as NE
import qualified Reporting.Error as Error
import qualified Reporting.Exit as Exit

-- | Convert compilation results into final build artifacts.
--
-- Assembles all compilation results, dependency information, and root
-- modules into a cohesive artifact structure. This function performs
-- the final aggregation step of the build process.
--
-- ==== Artifact Assembly Process
--
-- 1. Gather and segregate problems from successful compilations
-- 2. Collect root modules from compilation results  
-- 3. Assemble internal dependency modules using 'Processing' module
-- 4. Package everything into final 'Artifacts' structure
--
-- ==== Parameters
--
-- [@env@]: Build environment with project information
-- [@foreigns@]: Foreign dependency interfaces  
-- [@results@]: Map of compilation results by module name
-- [@rootResults@]: Results for root (entry point) modules
--
-- ==== Error Conditions
--
-- Returns 'Exit.BuildBadModules' when any compilation errors are present.
-- All errors are collected and reported together for comprehensive
-- error reporting.
--
-- @since 0.19.1
toArtifacts :: Env -> Dependencies -> Map.Map ModuleName.Raw Result -> NE.List RootResult -> Either Exit.BuildProblem Artifacts
toArtifacts (Env _ root projectType _ _ _ _) foreigns results rootResults =
  case gatherProblemsOrMains results rootResults of
    Left (NE.List e es) ->
      Left (Exit.BuildBadModules root e es)
    Right roots ->
      Right . Artifacts (projectTypeToPkg projectType) foreigns roots $
        assembleInternalModules results rootResults

-- | Assemble internal modules using processing functions.
--
-- Coordinates with the Processing module to build the complete list of
-- internal modules, ensuring proper handling of both root and non-root
-- modules.
--
-- @since 0.19.1
assembleInternalModules :: Map.Map ModuleName.Raw Result -> NE.List RootResult -> [Module]
assembleInternalModules results rootResults =
  Map.foldrWithKey (Processing.addInsideSafe rootResults) 
    (Foldable.foldr (Processing.addOutside results) [] rootResults) 
    results

-- | Gather compilation problems or successful main modules.
--
-- Segregates compilation results into either a list of errors (if any
-- compilation failed) or a list of successfully compiled root modules.
-- This ensures that either all roots succeed or all errors are reported.
--
-- ==== Result Processing
--
-- * Successful roots become 'Root' entries
-- * Compilation errors are collected for reporting
-- * Blocked dependencies are ignored (treated as non-critical)
--
-- @since 0.19.1
gatherProblemsOrMains :: Map.Map ModuleName.Raw Result -> NE.List RootResult -> Either (NE.List Error.Module) (NE.List Root)
gatherProblemsOrMains results (NE.List rootResult rootResults) =
  let errors = Map.foldr addErrors [] results
      processedResults = Foldable.foldr (addRootResult errors) (errors, []) rootResults
   in processFirstRoot rootResult processedResults

-- | Add root result to accumulator.
--
-- Processes a single root result and adds it to the accumulating lists
-- of errors and successful roots. Handles all root result types
-- appropriately.
--
-- ==== Root Result Types
--
-- * 'RInside': Internal root module (added to roots)
-- * 'ROutsideOk': Successfully compiled external root (added to roots)  
-- * 'ROutsideErr': Failed external root (added to errors)
-- * 'ROutsideBlocked': Blocked root (ignored)
--
-- @since 0.19.1
addRootResult :: [Error.Module] -> RootResult -> ([Error.Module], [Root]) -> ([Error.Module], [Root])
addRootResult _ result (es, roots) =
  case result of
    RInside n -> (es, Inside n : roots)
    ROutsideOk n i o -> (es, Outside n i o : roots)
    ROutsideErr e -> (e : es, roots)
    ROutsideBlocked -> (es, roots)

-- | Process the first root result.
--
-- Handles the first root result specially to ensure proper error
-- propagation and root collection. The first root determines the
-- overall success or failure of the root processing phase.
--
-- @since 0.19.1
processFirstRoot :: RootResult -> ([Error.Module], [Root]) -> Either (NE.List Error.Module) (NE.List Root)
processFirstRoot rootResult (errors, roots) =
  case rootResult of
    RInside n -> finalizeRootResults (Inside n) errors roots
    ROutsideOk n i o -> finalizeRootResults (Outside n i o) errors roots
    ROutsideErr e -> Left (NE.List e errors)
    ROutsideBlocked -> processBlockedFirstRoot errors

-- | Finalize root results or report errors.
--
-- Makes the final decision whether to return successful roots or
-- report accumulated errors. If any errors exist, they take precedence
-- over successful compilations.
--
-- @since 0.19.1
finalizeRootResults :: Root -> [Error.Module] -> [Root] -> Either (NE.List Error.Module) (NE.List Root)
finalizeRootResults firstRoot errors roots =
  case errors of
    [] -> Right (NE.List firstRoot roots)
    e : es -> Left (NE.List e es)

-- | Process blocked first root.
--
-- Handles the case where the first root result is blocked, typically
-- due to missing dependencies or circular imports. If no other errors
-- exist, this indicates a corrupted build state.
--
-- @since 0.19.1
processBlockedFirstRoot :: [Error.Module] -> Either (NE.List Error.Module) (NE.List Root)
processBlockedFirstRoot errors =
  case errors of
    [] -> error "seems like canopy-stuff/ is corrupted"
    e : es -> Left (NE.List e es)

-- | Add compilation errors to error list.
--
-- Extracts compilation errors from results and adds them to the
-- accumulating error list for comprehensive error reporting.
-- Only 'RProblem' results contribute actual errors.
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

-- | Convert project type to package name.
--
-- Helper function to resolve package names from project types.
-- This is used internally for artifact package identification.
--
-- ==== Project Type Mapping
--
-- * 'Parse.Package': Uses the specified package name
-- * 'Parse.Application': Uses a dummy package name for applications
--
-- @since 0.19.1
projectTypeToPkg :: Parse.ProjectType -> Pkg.Name
projectTypeToPkg projectType =
  case projectType of
    Parse.Package pkg -> pkg
    Parse.Application -> Pkg.dummyName