{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Configuration types for module checking.
--
-- This module contains all configuration record types used throughout
-- the module checking system, with proper lens generation following
-- CLAUDE.md standards.
--
-- === Configuration Overview
--
-- @
-- Configuration Types:
-- ├── ModuleStatusConfig   -> Status processing configuration
-- ├── CachedConfig        -> Cached module configuration
-- ├── ChangedConfig       -> Changed module configuration
-- ├── SameDepsConfig      -> Same dependencies configuration
-- └── CachedImportConfig  -> Cached import problem configuration
-- @
--
-- === Usage Examples
--
-- @
-- -- Create module status configuration
-- let config = ModuleStatusConfig env foreigns resultsMVar moduleName
--
-- -- Create cached module configuration
-- let cachedConfig = CachedConfig env projectType moduleName localDetails
--
-- -- Use lens to access configuration
-- let env = config ^. moduleStatusEnv
-- @
--
-- === Lens Usage
--
-- All configuration records follow CLAUDE.md lens conventions:
--
-- * Use lenses for access and updates
-- * Use record construction for initial creation
-- * Prefix lens names with record type
--
-- @since 0.19.1
module Build.Module.Check.Config
  ( -- * Configuration Types
    ModuleStatusConfig(..)
  , CachedConfig(..)
  , ChangedConfig(..)
  , SameDepsConfig(..)
  , CachedImportConfig(..)
  
  -- * Configuration Lenses
  , moduleStatusEnv
  , moduleStatusForeigns  
  , moduleStatusResultsMVar
  , moduleStatusName
  , cachedEnv
  , cachedProjectType
  , cachedModuleName
  , cachedLocal
  , changedEnv
  , changedModuleName
  , changedLocal
  , changedSource
  , changedModule
  , changedDocsNeed
  , changedImports
  , sameDepsEnv
  , sameDepsLocal
  , sameDepsSource
  , sameDepsModule
  , sameDepsDocsNeed
  , cachedImportEnv
  , cachedImportProjectType
  , cachedImportModuleName
  , cachedImportPath
  ) where

import Control.Concurrent.STM (TVar)
import Control.Lens (makeLenses)
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Data.ByteString as B
import qualified Parse.Module as Parse

import Build.Types
  ( Env
  , Dependencies
  , ResultDict
  , DocsNeed
  )

-- | Configuration for module status processing.
data ModuleStatusConfig = ModuleStatusConfig
  { _moduleStatusEnv :: !Env
  , _moduleStatusForeigns :: !Dependencies
  , _moduleStatusResultsMVar :: !(TVar ResultDict)
  , _moduleStatusName :: !ModuleName.Raw
  } deriving ()

-- | Configuration for cached module processing.
data CachedConfig = CachedConfig
  { _cachedEnv :: !Env
  , _cachedProjectType :: !Parse.ProjectType
  , _cachedModuleName :: !ModuleName.Raw
  , _cachedLocal :: !Details.Local
  } deriving ()

-- | Configuration for changed module processing.
data ChangedConfig = ChangedConfig
  { _changedEnv :: !Env
  , _changedModuleName :: !ModuleName.Raw
  , _changedLocal :: !Details.Local
  , _changedSource :: !B.ByteString
  , _changedModule :: !Src.Module
  , _changedDocsNeed :: !DocsNeed
  , _changedImports :: ![Src.Import]
  } deriving ()

-- | Configuration for handling same dependencies.
data SameDepsConfig = SameDepsConfig
  { _sameDepsEnv :: !Env
  , _sameDepsLocal :: !Details.Local
  , _sameDepsSource :: !B.ByteString
  , _sameDepsModule :: !Src.Module
  , _sameDepsDocsNeed :: !DocsNeed
  } deriving ()

-- | Configuration for cached import problem handling.
data CachedImportConfig = CachedImportConfig
  { _cachedImportEnv :: !Env
  , _cachedImportProjectType :: !Parse.ProjectType
  , _cachedImportModuleName :: !ModuleName.Raw
  , _cachedImportPath :: !FilePath
  } deriving ()

-- Generate lenses for all configuration records
makeLenses ''ModuleStatusConfig
makeLenses ''CachedConfig
makeLenses ''ChangedConfig
makeLenses ''SameDepsConfig
makeLenses ''CachedImportConfig