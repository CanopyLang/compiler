{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Module checking functionality for the Build system.
--
-- This module serves as the coordinating interface for module checking and compilation,
-- providing a clean API over the decomposed sub-modules. All functionality has been
-- split into focused modules following CLAUDE.md standards.
--
-- === Module Organization
--
-- @
-- Build.Module.Check
-- ├── Build.Module.Check.Status    -- Status processing logic
-- └── Build.Module.Check.Workflow  -- Compilation workflow
-- @
--
-- === Usage Examples
--
-- @
-- -- Check a module with the provided configuration
-- result <- checkModule checkConfig moduleName moduleStatus
--
-- -- Process specific status types
-- result <- processCachedStatus env resultsMVar moduleName localDetails
-- result <- processChangedStatus env resultsMVar moduleName localDetails source module docsNeed
--
-- -- Compile a module directly
-- result <- compile env docsNeed localDetails source interfaces module
-- @
--
-- === Thread Safety
--
-- All module checking operations are thread-safe through proper MVar usage
-- and immutable data structures.
--
-- @since 0.19.1
module Build.Module.Check
  ( -- * Main Checking Functions
    checkModule
  
  -- * Re-exports from Build.Module.Check.Status
  , module Build.Module.Check.Status
  
  -- * Re-exports from Build.Module.Check.Workflow  
  , module Build.Module.Check.Workflow
  ) where

import Data.Vector.Internal.Check (HasCallStack)
import Control.Lens ((^.))
import qualified Canopy.ModuleName as ModuleName

import Build.Config (CheckConfig, checkEnv, checkForeigns, checkResultsMVar)
import Build.Types (Result, Status)

-- Import sub-modules for re-export
import Build.Module.Check.Status
import Build.Module.Check.Workflow

-- | Check module using configuration record.
--
-- Main entry point for module checking that dispatches to the appropriate
-- status processing logic based on the module's current state.
--
-- ==== Parameters
--
-- [@config@] Check configuration with environment and dependencies
-- [@name@] Module name to check
-- [@status@] Current module status
--
-- ==== Returns
--
-- IO action producing the checking result
checkModule :: HasCallStack => CheckConfig -> ModuleName.Raw -> Status -> IO Result
checkModule config name status = do
  let env = config ^. checkEnv
  let foreigns = config ^. checkForeigns
  let resultsMVar = config ^. checkResultsMVar
  processModuleStatus env foreigns resultsMVar name status