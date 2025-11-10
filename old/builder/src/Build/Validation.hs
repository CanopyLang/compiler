{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Comprehensive validation and error checking for the Canopy build system.
--
-- This module serves as the coordinating interface for all validation
-- functionality in the build system. It provides a unified API for
-- dependency validation, root module checking, import error handling,
-- and build result finalization.
--
-- === Module Organization
--
-- The validation system is organized into focused sub-modules:
--
-- * "Build.Validation.Cycles" - Dependency cycle detection
-- * "Build.Validation.Roots" - Root module uniqueness validation
-- * "Build.Validation.Imports" - Import error generation and reporting
-- * "Build.Validation.Details" - Build details persistence and exposed modules
-- * "Build.Validation.Repl" - REPL artifact management and interactive compilation
-- * "Build.Validation.Results" - Result coordination (re-exports Details and Repl)
--
-- === Primary Functionality
--
-- * **Cycle Detection**: Identify circular dependencies in module graphs
-- * **Root Validation**: Ensure root modules are unique and well-formed
-- * **Import Validation**: Generate detailed import error reports with suggestions
-- * **Result Finalization**: Handle build completion and artifact generation
-- * **REPL Support**: Specialized validation for interactive compilation
--
-- === Usage Examples
--
-- @
-- -- Check for dependency cycles
-- case checkForCycles moduleStatuses of
--   Nothing -> putStrLn "No cycles detected"
--   Just (NE.List cycle) -> reportCyclicDependency cycle
--
-- -- Validate root uniqueness
-- case checkUniqueRoots statuses rootStatuses of
--   Nothing -> putStrLn "All roots are unique"
--   Just problem -> handleRootProblem problem
--
-- -- Generate import error reports
-- let errors = toImportErrors env results imports problems
-- reportImportErrors errors
--
-- -- Finalize build results
-- result <- finalizeExposed root docsGoal exposedModules results
-- case result of
--   Left problems -> handleBuildErrors problems
--   Right docs -> saveDocs docs
-- @
--
-- === Validation Process
--
-- The complete validation process follows these coordinated steps:
--
-- 1. **Dependency Analysis**: Build dependency graph and detect cycles
-- 2. **Root Validation**: Ensure root modules are unique and well-formed  
-- 3. **Import Checking**: Validate all imports resolve correctly
-- 4. **Result Finalization**: Package successful results and report errors
-- 5. **Artifact Generation**: Create build artifacts and documentation
--
-- === Error Reporting Strategy
--
-- The validation system provides comprehensive error reporting:
--
-- * **Focused Messages**: Return first error found for clear user guidance
-- * **Rich Context**: Include available modules and helpful suggestions
-- * **Source Locations**: Map errors to exact source code positions
-- * **Actionable Advice**: Provide specific steps to resolve issues
--
-- === Performance Characteristics
--
-- * **Dependency Analysis**: O(V + E) where V = modules, E = dependencies
-- * **Root Validation**: O(n log n) where n = number of root modules
-- * **Import Processing**: O(m + k) where m = imports, k = known modules
-- * **Result Finalization**: O(r) where r = compilation results
--
-- === Thread Safety
--
-- All validation functions are pure and thread-safe. Build result writing
-- uses atomic file operations to ensure consistency during concurrent builds.
-- REPL operations are designed for single-threaded interactive use.
--
-- @since 0.19.1
module Build.Validation
  ( -- * Re-exports from focused sub-modules
    module Build.Validation.Cycles
  , module Build.Validation.Roots
  , module Build.Validation.Imports
  , module Build.Validation.Results
  ) where

-- Re-export all functionality from sub-modules
import Build.Validation.Cycles
import Build.Validation.Roots  
import Build.Validation.Imports
import Build.Validation.Results