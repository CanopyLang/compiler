{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Configuration types and utilities for the Build system.
--
-- This module provides configuration record types to reduce parameter counts
-- in functions and enable better composition. All records support lens access.
module Build.Config
  ( -- * Configuration Records
    CheckConfig (..)
  , CrawlConfig (..)
  , CompileConfig (..)
  , DepsConfig (..)
  
  -- * Lenses
  , checkEnv
  , checkForeigns
  , checkResultsMVar
  , crawlEnv
  , crawlMVar
  , crawlDocsNeed
  , compileEnv
  , compileDocsNeed
  , compileLocal
  , compileSource
  , depsRoot
  , depsResults
  , depsList
  , depsLastCompile
  ) where

import Control.Concurrent.MVar (MVar)
import Control.Lens (makeLenses)
import qualified Data.ByteString as B
import Data.Map.Strict (Map)
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Interface as I
import qualified Canopy.Details as Details

-- Note: Configuration types are defined in Build.Types to avoid circular imports.
-- This module re-exports them for convenience.

-- Re-export configuration types from Build.Types
import Build.Types
  ( CheckConfig (..)
  , CrawlConfig (..)
  , CompileConfig (..)
  , DepsConfig (..)
  , checkEnv
  , checkForeigns
  , checkResultsMVar
  , crawlEnv
  , crawlMVar
  , crawlDocsNeed
  , compileEnv
  , compileDocsNeed
  , compileLocal
  , compileSource
  , depsRoot
  , depsResults
  , depsList
  , depsLastCompile
  )