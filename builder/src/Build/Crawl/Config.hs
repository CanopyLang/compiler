{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Configuration types and utilities for module processing.
--
-- This module provides focused configuration management for the crawling
-- system, including:
--
-- * Configuration record types for different processing stages
-- * Lens generation for configuration access
-- * Configuration transformation utilities
-- * Type-safe configuration management
--
-- The configuration system uses focused records to manage the complexity
-- of different processing stages while maintaining type safety and clarity:
--
-- @
-- 1. ProcessPathConfig: Path discovery and resolution
-- 2. SinglePathConfig: Single path validation  
-- 3. LocalPathConfig: Local module processing
-- 4. ParseConfig: Module parsing and validation
-- 5. ValidationConfig: Module name validation
-- @
--
-- === Usage Examples
--
-- @
-- -- Create path processing configuration
-- pathConfig <- ProcessPathConfig env mvar docsNeed name paths root projectType buildID locals foreigns
--
-- -- Transform configurations between stages
-- singleConfig <- createSinglePathConfig pathConfig path
-- localConfig <- createLocalPathConfig singleConfig
-- @
--
-- === Configuration Lifecycle
--
-- Configurations flow through processing stages in a type-safe manner:
-- ProcessPath -> SinglePath -> LocalPath -> Parse -> Validation
--
-- @since 0.19.1
module Build.Crawl.Config
  ( -- * Configuration Types
    ProcessPathConfig (..)
  , SinglePathConfig (..)
  , LocalPathConfig (..)
  , ParseConfig (..)
  , ValidationConfig (..)
    -- * Configuration Lenses
  , pathConfigEnv, pathConfigMVar, pathConfigDocsNeed, pathConfigName
  , pathConfigPaths, pathConfigRoot, pathConfigProjectType, pathConfigBuildID
  , pathConfigLocals, pathConfigForeigns
  , singlePathEnv, singlePathMVar, singlePathDocsNeed, singlePathName
  , singlePathPath, singlePathBuildID, singlePathLocals, singlePathForeigns
  , localPathEnv, localPathMVar, localPathDocsNeed, localPathName
  , localPathPath, localPathBuildID, localPathLocals
  , parseConfigEnv, parseConfigMVar, parseConfigDocsNeed, parseConfigExpectedName
  , parseConfigPath, parseConfigTime, parseConfigSource, parseConfigProjectType
  , parseConfigBuildID, parseConfigLastChange
  , validationConfigEnv, validationConfigMVar, validationConfigDocsNeed
  , validationConfigExpectedName, validationConfigActualName, validationConfigPath
  , validationConfigTime, validationConfigSource, validationConfigSrcModule
  , validationConfigImports, validationConfigValues, validationConfigBuildID
  , validationConfigLastChange, validationConfigName
    -- * Configuration Creation
  , createSinglePathConfig
  , createLocalPathConfig  
  , createValidationConfig
  ) where

import Control.Concurrent.MVar (MVar)
import Control.Lens (makeLenses, (^.))
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Data.ByteString as B
import Data.Map.Strict (Map)
import qualified File
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A

import Build.Types
  ( Env (..)
  , StatusDict
  , DocsNeed (..)
  )

-- | Configuration for processing module paths.
--
-- Contains all necessary context for processing discovered module paths,
-- including environment settings, concurrency primitives, and project
-- metadata needed for proper module resolution.
data ProcessPathConfig = ProcessPathConfig
  { _pathConfigEnv :: !Env
  , _pathConfigMVar :: !(MVar StatusDict)  
  , _pathConfigDocsNeed :: !DocsNeed
  , _pathConfigName :: !ModuleName.Raw
  , _pathConfigPaths :: ![FilePath]
  , _pathConfigRoot :: !FilePath
  , _pathConfigProjectType :: !Parse.ProjectType
  , _pathConfigBuildID :: !Details.BuildID
  , _pathConfigLocals :: !(Map ModuleName.Raw Details.Local)
  , _pathConfigForeigns :: !(Map ModuleName.Raw Details.Foreign)
  }

-- | Configuration for single path processing.
--
-- Used when exactly one module path is found during discovery.
-- Contains context needed to validate the path and process the
-- corresponding module file.
data SinglePathConfig = SinglePathConfig
  { _singlePathEnv :: !Env
  , _singlePathMVar :: !(MVar StatusDict)
  , _singlePathDocsNeed :: !DocsNeed
  , _singlePathName :: !ModuleName.Raw
  , _singlePathPath :: !FilePath
  , _singlePathBuildID :: !Details.BuildID
  , _singlePathLocals :: !(Map ModuleName.Raw Details.Local)
  , _singlePathForeigns :: !(Map ModuleName.Raw Details.Foreign)
  }

-- | Configuration for local path processing.
--
-- Used for processing modules that are part of the current project
-- (as opposed to foreign dependencies). Contains local-specific
-- context and validation requirements.
data LocalPathConfig = LocalPathConfig
  { _localPathEnv :: !Env
  , _localPathMVar :: !(MVar StatusDict)
  , _localPathDocsNeed :: !DocsNeed
  , _localPathName :: !ModuleName.Raw
  , _localPathPath :: !FilePath
  , _localPathBuildID :: !Details.BuildID
  , _localPathLocals :: !(Map ModuleName.Raw Details.Local)
  }

-- | Configuration for parsing and validation.
--
-- Contains all context needed for parsing module source code
-- and performing initial validation of the parsed AST.
data ParseConfig = ParseConfig
  { _parseConfigEnv :: !Env
  , _parseConfigMVar :: !(MVar StatusDict)
  , _parseConfigDocsNeed :: !DocsNeed
  , _parseConfigExpectedName :: !ModuleName.Raw
  , _parseConfigPath :: !FilePath
  , _parseConfigTime :: !File.Time
  , _parseConfigSource :: !B.ByteString
  , _parseConfigProjectType :: !Parse.ProjectType
  , _parseConfigBuildID :: !Details.BuildID
  , _parseConfigLastChange :: !Details.BuildID
  }

-- | Configuration for module validation.
--
-- Contains context needed for validating parsed modules,
-- including name consistency checks and dependency validation.
data ValidationConfig = ValidationConfig
  { _validationConfigEnv :: !Env
  , _validationConfigMVar :: !(MVar StatusDict)
  , _validationConfigDocsNeed :: !DocsNeed
  , _validationConfigExpectedName :: !ModuleName.Raw
  , _validationConfigActualName :: !ModuleName.Raw
  , _validationConfigPath :: !FilePath
  , _validationConfigTime :: !File.Time
  , _validationConfigSource :: !B.ByteString
  , _validationConfigSrcModule :: !Src.Module
  , _validationConfigImports :: ![Src.Import]
  , _validationConfigValues :: ![A.Located Src.Value]
  , _validationConfigBuildID :: !Details.BuildID
  , _validationConfigLastChange :: !Details.BuildID
  , _validationConfigName :: !(A.Located ModuleName.Raw)
  }

-- Generate lenses for all configuration records
makeLenses ''ProcessPathConfig
makeLenses ''SinglePathConfig
makeLenses ''LocalPathConfig
makeLenses ''ParseConfig
makeLenses ''ValidationConfig

-- | Create single path configuration from process path configuration.
--
-- Transforms a path processing configuration into a single path
-- configuration when exactly one module path is found.
--
-- @since 0.19.1
createSinglePathConfig
  :: ProcessPathConfig
  -- ^ Source path processing configuration
  -> FilePath
  -- ^ The single path found
  -> SinglePathConfig
  -- ^ Single path configuration for further processing
createSinglePathConfig cfg path = SinglePathConfig
  { _singlePathEnv = cfg ^. pathConfigEnv
  , _singlePathMVar = cfg ^. pathConfigMVar
  , _singlePathDocsNeed = cfg ^. pathConfigDocsNeed
  , _singlePathName = cfg ^. pathConfigName
  , _singlePathPath = path
  , _singlePathBuildID = cfg ^. pathConfigBuildID
  , _singlePathLocals = cfg ^. pathConfigLocals
  , _singlePathForeigns = cfg ^. pathConfigForeigns
  }

-- | Create local path configuration from single path configuration.
--
-- Transforms a single path configuration into a local path
-- configuration when the module is confirmed to be local
-- (not a foreign dependency).
--
-- @since 0.19.1
createLocalPathConfig
  :: SinglePathConfig
  -- ^ Source single path configuration
  -> LocalPathConfig
  -- ^ Local path configuration for local module processing
createLocalPathConfig cfg = LocalPathConfig
  { _localPathEnv = cfg ^. singlePathEnv
  , _localPathMVar = cfg ^. singlePathMVar
  , _localPathDocsNeed = cfg ^. singlePathDocsNeed
  , _localPathName = cfg ^. singlePathName
  , _localPathPath = cfg ^. singlePathPath
  , _localPathBuildID = cfg ^. singlePathBuildID
  , _localPathLocals = cfg ^. singlePathLocals
  }

-- | Create validation configuration from parse configuration.
--
-- Transforms parse configuration with parsed module information
-- into validation configuration for module name and structure validation.
--
-- @since 0.19.1
createValidationConfig
  :: ParseConfig
  -- ^ Source parse configuration
  -> ModuleName.Raw
  -- ^ Actual module name from parsed AST
  -> Src.Module
  -- ^ Parsed module AST
  -> [Src.Import]
  -- ^ Import declarations from parsed AST
  -> [A.Located Src.Value]
  -- ^ Value declarations from parsed AST
  -> A.Located ModuleName.Raw
  -- ^ Located module name for error reporting
  -> ValidationConfig
  -- ^ Validation configuration for module validation
createValidationConfig cfg actualName srcModule imports values name = ValidationConfig
  { _validationConfigEnv = cfg ^. parseConfigEnv
  , _validationConfigMVar = cfg ^. parseConfigMVar
  , _validationConfigDocsNeed = cfg ^. parseConfigDocsNeed
  , _validationConfigExpectedName = cfg ^. parseConfigExpectedName
  , _validationConfigActualName = actualName
  , _validationConfigPath = cfg ^. parseConfigPath
  , _validationConfigTime = cfg ^. parseConfigTime
  , _validationConfigSource = cfg ^. parseConfigSource
  , _validationConfigSrcModule = srcModule
  , _validationConfigImports = imports
  , _validationConfigValues = values
  , _validationConfigBuildID = cfg ^. parseConfigBuildID
  , _validationConfigLastChange = cfg ^. parseConfigLastChange
  , _validationConfigName = name
  }