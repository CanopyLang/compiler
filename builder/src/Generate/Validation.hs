{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Debug validation for the Generate subsystem.
--
-- This module provides validation functions to ensure code quality
-- and prevent common issues during code generation, particularly
-- around debug mode restrictions and production builds.
--
-- === Validation Rules
--
-- * Debug uses are not allowed in production builds
-- * All debug calls must be stripped for optimization
-- * Debug information must be properly tracked
--
-- === Usage Examples
--
-- @
-- -- Validate objects before production generation
-- objects <- finalizeObjects loading
-- checkForDebugUses objects  -- Throws error if debug found
-- 
-- -- Generate optimized production code
-- let graph = objectsToGlobalGraph objects
-- let mode = Mode.Prod (Mode.shortenFieldNames graph)
-- JS.generate mode graph mains
-- @
--
-- === Error Reporting
--
-- Validation errors include:
--
-- * Specific modules containing debug uses
-- * Exact locations of problematic debug calls
-- * Suggestions for fixing debug issues
--
-- @since 0.19.1
module Generate.Validation
  ( -- * Debug Validation
    checkForDebugUses
  ) where

import Control.Lens ((^.))
import qualified Data.Map as Map
import qualified Generate.Types as Types
import Generate.Types (Objects(..), Task)
import qualified Nitpick.Debug as Nitpick
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Check for debug uses in objects for production builds.
--
-- This function validates that no debug statements are present
-- in the codebase when generating optimized production builds.
-- Debug statements must be removed for proper optimization.
--
-- === Parameters
--
-- * 'objects': Objects container to validate for debug uses
--
-- === Returns
--
-- A Task that succeeds if no debug uses are found, or throws
-- a GenerateCannotOptimizeDebugValues error with the list of
-- modules containing debug statements.
--
-- === Validation Process
--
-- 1. Scan all local graphs for debug uses
-- 2. Collect modules with debug statements
-- 3. Throw error if any debug uses found
-- 4. Return successfully if no debug uses
--
-- === Examples
--
-- @
-- -- Validate before production generation
-- objects <- finalizeObjects loading
-- checkForDebugUses objects
-- 
-- -- If validation passes, generate optimized code
-- let graph = objectsToGlobalGraph objects
-- let mode = Mode.Prod (Mode.shortenFieldNames graph)
-- @
--
-- === Error Information
--
-- When debug uses are found, the error includes:
--
-- * Primary module with debug uses (first found)
-- * Additional modules with debug uses (if any)
-- * Helps identify all locations needing cleanup
--
-- @since 0.19.1
checkForDebugUses 
  :: Objects
  -- ^ Objects container to validate for debug uses
  -> Task ()
  -- ^ Task that fails if debug uses are found
checkForDebugUses objects =
  case Map.keys (Map.filter Nitpick.hasDebugUses (objects ^. Types.localGraphs)) of
    [] -> return ()
    m : ms -> Task.throw (Exit.GenerateCannotOptimizeDebugValues m ms)