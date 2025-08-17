{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Module processing and validation functionality for the Build system.
--
-- This module provides focused module processing capabilities including:
--
-- * Module source parsing and syntax validation
-- * Module name validation and consistency checking
-- * AST processing and dependency extraction
-- * Integration with path processing and configuration management
--
-- The processing system handles the core module validation:
--
-- @
-- 1. Source Parsing:
--    - Parse module source into AST
--    - Handle syntax errors with detailed reporting
--
-- 2. Name Validation:
--    - Validate module name consistency
--    - Check expected vs actual module names
--
-- 3. Module Processing:
--    - Extract dependencies and main function detection
--    - Create local module details for build tracking
-- @
--
-- === Usage Examples
--
-- @
-- -- Parse and validate module source
-- config <- createParseConfig env path time source
-- status <- parseAndValidate config
--
-- -- Validate module name consistency  
-- validationConfig <- createValidationConfig parseConfig actualName imports values name
-- status <- validateModuleName validationConfig
-- @
--
-- === Integration with Other Modules
--
-- This module integrates with:
--   * Build.Crawl.Config for configuration management
--   * Build.Crawl.Paths for path processing functionality
--   * Parse.Module for AST parsing
--   * AST.Source for AST types and utilities
--
-- @since 0.19.1
module Build.Crawl.Processing
  ( -- * Configuration Re-exports
    module Build.Crawl.Config
    -- * Path Processing Re-exports
  , module Build.Crawl.Paths
    -- * Main Crawling Functions
  , crawlModule
  , crawlFile
    -- * Module Processing
  , parseAndValidate
  , validateAndProcess
  , validateModuleName
  , processValidModule
    -- * Utilities
  , isMain
  ) where

import Control.Lens ((^.))
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Data.Name as Name
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Syntax as Syntax

import Build.Types (Status (..))
import Build.Crawl.Config
import Build.Crawl.Core (crawlModule, crawlFile)
import Build.Crawl.Paths
import qualified Build.Crawl.Dependencies as Deps

-- | Parse and validate module source.
--
-- Parses module source code and performs initial validation
-- of the resulting AST structure.
--
-- @since 0.19.1
parseAndValidate
  :: ParseConfig
  -- ^ Parse configuration
  -> IO Status
  -- ^ Parsing and validation status result
parseAndValidate config =
  case Parse.fromByteString (config ^. parseConfigProjectType) (config ^. parseConfigSource) of
    Left err -> pure $ SBadSyntax (config ^. parseConfigPath) (config ^. parseConfigTime) (config ^. parseConfigSource) err
    Right modul -> validateAndProcess config modul

-- | Validate module name and process.
--
-- Extracts module name from parsed AST and validates it
-- against expected naming conventions.
--
-- @since 0.19.1
validateAndProcess
  :: ParseConfig
  -- ^ Parse configuration
  -> Src.Module
  -- ^ Parsed module AST
  -> IO Status
  -- ^ Validation status result
validateAndProcess config (Src.Module maybeActualName _ _ imports values _ _ _ _) =
  case maybeActualName of
    Nothing -> pure $ SBadSyntax (config ^. parseConfigPath) (config ^. parseConfigTime) (config ^. parseConfigSource) (Syntax.ModuleNameUnspecified (config ^. parseConfigExpectedName))
    Just name@(A.At _ actualName) -> validateModuleName (createValidationConfig config actualName imports values name)

-- | Validate module name matches expected.
--
-- Ensures that the module name declared in the source matches
-- the expected name based on file path and project structure.
--
-- @since 0.19.1
validateModuleName
  :: ValidationConfig
  -- ^ Validation configuration
  -> IO Status
  -- ^ Validation status result
validateModuleName config =
  if config ^. validationConfigExpectedName == config ^. validationConfigActualName
    then processValidModule config
    else pure $ SBadSyntax (config ^. validationConfigPath) (config ^. validationConfigTime) (config ^. validationConfigSource) (Syntax.ModuleNameMismatch (config ^. validationConfigExpectedName) (config ^. validationConfigName))

-- | Process valid module.
--
-- Creates local module details and initiates dependency crawling
-- for a successfully validated module.
--
-- @since 0.19.1
processValidModule
  :: ValidationConfig
  -- ^ Validation configuration
  -> IO Status
  -- ^ Processing status result
processValidModule config = do
  let deps = fmap Src.getImportName (config ^. validationConfigImports)
  let local = Details.Local (config ^. validationConfigPath) (config ^. validationConfigTime) deps (any isMain (config ^. validationConfigValues)) (config ^. validationConfigLastChange) (config ^. validationConfigBuildID)
  Deps.crawlDeps (config ^. validationConfigEnv) (config ^. validationConfigMVar) deps (SChanged local (config ^. validationConfigSource) undefined (config ^. validationConfigDocsNeed))

-- | Check if value is main function.
--
-- Identifies main function declarations in module value definitions
-- for proper module categorization and build optimization.
--
-- @since 0.19.1
isMain
  :: A.Located Src.Value
  -- ^ Located value declaration
  -> Bool
  -- ^ Whether value is main function
isMain (A.At _ (Src.Value (A.At _ name) _ _ _)) = name == Name._main

-- The crawlModule and crawlFile functions are now imported from Build.Crawl.Core