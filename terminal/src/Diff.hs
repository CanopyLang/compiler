{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | API difference analysis and semantic versioning classification.
--
-- This module provides comprehensive API difference analysis for Canopy
-- packages, supporting multiple comparison modes with structured output
-- and semantic versioning magnitude classification. It follows CLAUDE.md
-- modular design patterns with specialized sub-modules for focused
-- responsibilities and maintainable architecture.
--
-- == Key Features
--
-- * Multi-mode diff analysis (global, local, code-based comparisons)
-- * Semantic versioning magnitude classification (MAJOR/MINOR/PATCH)
-- * Rich output formatting with color-coded change indicators
-- * Comprehensive error handling and user feedback
-- * Registry integration for published package access
-- * Local source code documentation generation
--
-- == Architecture
--
-- The module follows modular design patterns:
--
-- * 'Diff.Types' - Core data structures and lenses
-- * 'Diff.Environment' - Runtime environment setup and configuration
-- * 'Diff.Documentation' - Documentation loading and generation
-- * 'Diff.Execution' - Core diff execution logic and orchestration
-- * 'Diff.Output' - Result formatting and display
--
-- == Comparison Modes
--
-- Four primary diff comparison modes are supported:
--
-- * __Global Inquiry__ - Compare two published package versions
-- * __Local Inquiry__ - Compare local project versions
-- * __Code vs Latest__ - Compare local code against latest published version
-- * __Code vs Specific__ - Compare local code against specific published version
--
-- == Usage Examples
--
-- @
-- -- Compare local code against latest published version
-- main = run CodeVsLatest ()
--
-- -- Compare two published versions globally  
-- main = run (GlobalInquiry packageName version1 version2) ()
--
-- -- Compare local versions within project
-- main = run (LocalInquiry version1 version2) ()
-- @
--
-- == Error Handling
--
-- All operations use structured error handling with rich error types:
--
-- * 'Exit.DiffNoOutline' - No project outline found
-- * 'Exit.DiffBadOutline' - Invalid project outline
-- * 'Exit.DiffUnknownPackage' - Package not found in registry
-- * 'Exit.DiffDocsProblem' - Documentation loading failures
-- * 'Exit.DiffBadBuild' - Source compilation failures
--
-- == Integration
--
-- The module integrates with the broader Canopy toolchain:
--
-- * Package registry system for version lookups
-- * Build system for documentation generation
-- * Terminal framework for command-line interface
-- * Reporting system for structured error output
--
-- @since 0.19.1
module Diff
  ( -- * Core Types (re-exported)
    Args (..),
    
    -- * Main Interface
    run,
  )
where

import Diff.Types (Args (..))
import qualified Diff.Environment as Environment
import qualified Diff.Execution as Execution
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Main entry point for diff operations.
--
-- Initializes the runtime environment, executes the requested diff
-- operation, and handles all errors through the structured reporting
-- system. Provides unified interface for all diff comparison modes.
--
-- The execution flow:
--
-- 1. 'Environment.setup' - Initialize runtime environment
-- 2. 'Execution.run' - Execute diff operation with error handling
-- 3. Error reporting through structured exit codes
--
-- ==== Examples
--
-- >>> run CodeVsLatest ()
-- -- Compare local source against latest published version
--
-- >>> run (GlobalInquiry pkg v1 v2) ()
-- -- Compare two published versions of a package
--
-- >>> run (LocalInquiry v1 v2) ()
-- -- Compare two local versions within project
--
-- ==== Error Conditions
--
-- Handles and reports all error conditions:
--   * Environment setup failures
--   * Package resolution problems
--   * Documentation loading issues
--   * Build and compilation errors
--   * Network connectivity problems
--
-- @since 0.19.1
run :: Args -> () -> IO ()
run args () =
  Reporting.attempt Exit.diffToReport (Task.run executeWithEnvironment)
  where
    executeWithEnvironment = do
      env <- Environment.setup
      Execution.run env args