{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Path processing functionality for module crawling.
--
-- This module provides focused path processing capabilities including:
--
-- * Module path resolution and validation
-- * Ambiguous path handling and error reporting
-- * Foreign and kernel module path processing
-- * Local vs foreign path discrimination
--
-- The path processing system handles different scenarios:
--
-- @
-- 1. Single Path: Exactly one module file found
-- 2. Multiple Paths: Ambiguous module resolution
-- 3. No Paths: Check for foreign or kernel modules
-- 4. Existing Local: Cache validation and recrawling decisions
-- @
--
-- === Usage Examples
--
-- @
-- -- Process discovered module paths
-- status <- processModulePaths config
-- 
-- -- Handle single path processing
-- status <- processSinglePath singleConfig
--
-- -- Check for recrawling needs
-- needsRecrawl <- shouldRecrawl newPath newTime oldPath oldTime docsNeed
-- @
--
-- === Path Resolution Strategy
--
-- Path processing follows a hierarchical resolution strategy:
--   1. Check for local module conflicts with foreign dependencies
--   2. Validate path accessibility and modification times
--   3. Determine if recrawling is needed based on cache status
--   4. Handle foreign and kernel module fallbacks
--
-- @since 0.19.1
module Build.Crawl.Paths
  ( -- * Path Processing
    processModulePaths
  , processSinglePath
  , processLocalPath
  , processExistingLocal
    -- * Path Resolution
  , processAmbiguousPaths
  , processNoPath
    -- * Foreign and Kernel Processing
  , processForeignModule
  , processKernelModule
    -- * Utilities
  , shouldRecrawl
  ) where

import Control.Concurrent.MVar (MVar)
import Control.Lens ((^.))
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified File
import qualified Parse.Module as Parse
import qualified Reporting.Error.Import as Import
import qualified System.FilePath as FP

import Build.Types
  ( Env (..)
  , Status (..)
  , StatusDict
  , DocsNeed (..)
  )
import Build.Crawl.Config
import qualified Build.Crawl.Core as Core
import qualified Build.Crawl.Discovery as Discovery

-- | Process discovered module paths based on count and type.
--
-- Handles different scenarios:
--   * Single path: Process normally
--   * Multiple paths: Report ambiguity error  
--   * No paths: Check for foreign or kernel modules
--
-- @since 0.19.1
processModulePaths
  :: ProcessPathConfig
  -- ^ Path processing configuration
  -> IO Status
  -- ^ Processing status result
processModulePaths config =
  case config ^. pathConfigPaths of
    [path] -> processSinglePath (createSinglePathConfig config path)
    p1 : p2 : ps -> processAmbiguousPaths (config ^. pathConfigRoot) p1 p2 ps
    [] -> processNoPath (config ^. pathConfigName) (config ^. pathConfigProjectType) (config ^. pathConfigForeigns)

-- | Process single discovered path.
--
-- Checks if the module is a foreign dependency that conflicts
-- with a local module, otherwise proceeds with local processing.
--
-- @since 0.19.1
processSinglePath
  :: SinglePathConfig
  -- ^ Single path configuration
  -> IO Status
  -- ^ Processing status result
processSinglePath config =
  case Map.lookup (config ^. singlePathName) (config ^. singlePathForeigns) of
    Just (Details.Foreign dep deps) -> pure . SBadImport $ Import.Ambiguous (config ^. singlePathPath) [] dep deps
    Nothing -> processLocalPath (createLocalPathConfig config)

-- | Process local module path.
--
-- Handles local module processing by checking for existing
-- cached versions and determining if recrawling is needed.
--
-- @since 0.19.1
processLocalPath
  :: LocalPathConfig
  -- ^ Local path configuration
  -> IO Status
  -- ^ Processing status result
processLocalPath config = do
  newTime <- File.getTime (config ^. localPathPath)
  case Map.lookup (config ^. localPathName) (config ^. localPathLocals) of
    Nothing -> crawlFile (config ^. localPathEnv) (config ^. localPathMVar) (config ^. localPathDocsNeed) (config ^. localPathName) (config ^. localPathPath) newTime (config ^. localPathBuildID)
    Just local -> processExistingLocal (config ^. localPathEnv) (config ^. localPathMVar) (config ^. localPathDocsNeed) (config ^. localPathName) (config ^. localPathPath) newTime local

-- | Process existing local module.
--
-- Determines whether to use cached version or recrawl based on
-- file modification time, path changes, and documentation needs.
--
-- @since 0.19.1
processExistingLocal
  :: Env
  -- ^ Build environment
  -> MVar StatusDict
  -- ^ Status dictionary for coordination
  -> DocsNeed
  -- ^ Documentation generation requirements
  -> ModuleName.Raw
  -- ^ Module name being processed
  -> FilePath
  -- ^ Current module file path
  -> File.Time
  -- ^ Current file modification time
  -> Details.Local
  -- ^ Existing local module details
  -> IO Status
  -- ^ Processing status result
processExistingLocal env mvar docsNeed name path newTime local =
  let oldPath = local ^. Details.path
      oldTime = local ^. Details.time
      deps = local ^. Details.deps
      lastChange = local ^. Details.lastChange
  in if shouldRecrawl path newTime oldPath oldTime docsNeed
    then crawlFile env mvar docsNeed name path newTime lastChange
    else crawlDeps env mvar deps (SCached local)

-- | Process ambiguous module paths.
--
-- Creates an error status when multiple module files are found
-- for the same module name, providing clear error information.
--
-- @since 0.19.1
processAmbiguousPaths
  :: FilePath
  -- ^ Project root path for relative path calculation
  -> FilePath
  -- ^ First ambiguous path
  -> FilePath
  -- ^ Second ambiguous path
  -> [FilePath]
  -- ^ Additional ambiguous paths
  -> IO Status
  -- ^ Error status for ambiguous paths
processAmbiguousPaths root p1 p2 ps =
  pure . SBadImport $ Import.AmbiguousLocal 
    (FP.makeRelative root p1) 
    (FP.makeRelative root p2) 
    (fmap (FP.makeRelative root) ps)

-- | Process case where no module path found.
--
-- Checks for foreign dependencies or kernel modules when
-- no local module file is found.
--
-- @since 0.19.1
processNoPath
  :: ModuleName.Raw
  -- ^ Module name being searched
  -> Parse.ProjectType
  -- ^ Project type (affects kernel module handling)
  -> Map ModuleName.Raw Details.Foreign
  -- ^ Foreign dependency mappings
  -> IO Status
  -- ^ Processing status result
processNoPath name projectType foreigns =
  case Map.lookup name foreigns of
    Just (Details.Foreign dep deps) -> processForeignModule dep deps
    Nothing -> processKernelModule name projectType

-- | Process foreign module dependency.
--
-- Handles foreign module resolution and ambiguity checking
-- for dependencies from other packages.
--
-- @since 0.19.1
processForeignModule
  :: Pkg.Name
  -- ^ Primary foreign dependency
  -> [Pkg.Name]
  -- ^ Additional foreign dependencies (potential ambiguity)
  -> IO Status
  -- ^ Foreign module processing status
processForeignModule dep deps =
  case deps of
    [] -> pure $ SForeign dep
    d : ds -> pure . SBadImport $ Import.AmbiguousForeign dep d ds

-- | Process potential kernel module.
--
-- Checks if a module name represents a kernel module and
-- validates its existence if kernel modules are allowed.
--
-- @since 0.19.1
processKernelModule
  :: ModuleName.Raw
  -- ^ Module name to check
  -> Parse.ProjectType
  -- ^ Project type (determines kernel module support)
  -> IO Status
  -- ^ Kernel module processing status
processKernelModule name projectType =
  if Name.isKernel name && Parse.isKernel projectType
    then checkKernelExists name
    else pure $ SBadImport Import.NotFound

-- | Check if module should be recrawled.
--
-- Determines whether a module needs to be reprocessed based on
-- file changes, path changes, or documentation generation needs.
--
-- @since 0.19.1
shouldRecrawl
  :: FilePath
  -- ^ Current file path
  -> File.Time
  -- ^ Current file modification time
  -> FilePath
  -- ^ Previous file path
  -> File.Time
  -- ^ Previous file modification time
  -> DocsNeed
  -- ^ Documentation generation requirements
  -> Bool
  -- ^ Whether recrawling is needed
shouldRecrawl path newTime oldPath oldTime docsNeed =
  path /= oldPath || oldTime /= newTime || Build.Crawl.Paths.needsDocs docsNeed

-- | Check if documentation generation is needed.
--
-- Determines whether documentation should be generated based
-- on the current documentation requirements.
--
-- @since 0.19.1
needsDocs
  :: DocsNeed
  -- ^ Documentation requirements
  -> Bool
  -- ^ Whether documentation is needed
needsDocs (DocsNeed need) = need

-- | Crawl file - imported from Core module
crawlFile :: Env -> MVar StatusDict -> DocsNeed -> ModuleName.Raw -> FilePath -> File.Time -> Details.BuildID -> IO Status
crawlFile = Core.crawlFile

-- | Crawl dependencies - imported from Core module  
crawlDeps :: Env -> MVar StatusDict -> [ModuleName.Raw] -> a -> IO a  
crawlDeps = Core.crawlDeps

-- | Check kernel exists - imported from Discovery module
checkKernelExists :: ModuleName.Raw -> IO Status
checkKernelExists = Discovery.checkKernelExists