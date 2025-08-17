{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Build result finalization and management coordination.
--
-- This module serves as a coordinating interface for build result
-- finalization functionality. It provides a unified API for build
-- details persistence, exposed module finalization, and REPL artifact
-- management.
--
-- === Module Organization
--
-- Result management is organized into focused sub-modules:
--
-- * "Build.Validation.Details" - Build details persistence and exposed modules
-- * "Build.Validation.Repl" - REPL artifact management and interactive compilation
--
-- === Primary Functionality
--
-- * **Build Details**: Persist compilation results and manage project details
-- * **Exposed Modules**: Finalize exposed module compilation and documentation
-- * **REPL Artifacts**: Handle interactive compilation and artifact generation
-- * **Error Collection**: Gather and categorize build errors for reporting
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
--
-- -- Handle REPL artifacts
-- let config = ReplConfig env source modul resultMVars
-- artifacts <- finalizeReplArtifacts config depsStatus results
-- @
--
-- === Thread Safety
--
-- Build result operations use atomic file writing and immutable data structures
-- to ensure consistency during concurrent builds. REPL operations are designed
-- for single-threaded interactive use.
--
-- @since 0.19.1
module Build.Validation.Results
  ( -- * Re-exports from sub-modules
    module Build.Validation.Details
  , module Build.Validation.Repl
  ) where

-- Re-export all functionality from sub-modules
import Build.Validation.Details
import Build.Validation.Repl