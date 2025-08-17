{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Core crawling functionality for the Build system.
--
-- This module provides the core module crawling functions that are used by
-- both the Processing and Dependencies modules. By separating these functions
-- into a shared core module, we avoid circular dependencies between the
-- specialized modules.
--
-- === Primary Functions
--
-- * 'crawlFile': Core file crawling with validation
-- * 'crawlModule': Main module crawling entry point
--
-- === Usage Examples
--
-- @
-- -- Crawl a specific file
-- status <- crawlFile env mvar docsNeed name path time buildID
-- 
-- -- Crawl a module by name
-- status <- crawlModule config moduleName
-- @
--
-- === Architecture
--
-- This module serves as the foundation that other crawling modules build upon:
--   * Dependencies can call crawlModule without importing Processing
--   * Processing can implement specialized functionality without circular deps
--   * Paths can call crawlFile without importing Processing
--
-- @since 0.19.1
module Build.Crawl.Core
  ( -- * Core Crawling Functions
    crawlFile
  , crawlModule
  , crawlDeps
  , crawlNewDep
  , fork
    -- * Module Processing
  , parseAndValidateModule
  , processValidatedModule
    -- * Utilities
  , isMainValue
  ) where

import Control.Concurrent.MVar (MVar)
import Control.Lens ((^.))
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Name as Name
import qualified Data.ByteString as B
import qualified Data.Map.Strict as Map
import qualified File
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Import as Import
import qualified Reporting.Error.Syntax as Syntax
import System.FilePath ((</>))

import Build.Config (CrawlConfig (..), crawlEnv, crawlMVar, crawlDocsNeed)
import Build.Types (Env (..), Status (..), StatusDict, DocsNeed (..))
import qualified Build.Crawl.Discovery as Discovery

-- For dependency crawling
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (takeMVar, putMVar, newEmptyMVar, readMVar)
import qualified Data.Set as Set
import Data.Foldable (traverse_)

-- | Crawl file with validation.
--
-- Processes a specific module file by reading its contents, parsing,
-- and validating the module structure. This is the core file processing
-- function that coordinates parsing and validation operations.
--
-- @since 0.19.1
crawlFile
  :: Env
  -- ^ Build environment
  -> MVar StatusDict
  -- ^ Status dictionary for coordination
  -> DocsNeed
  -- ^ Documentation generation requirements
  -> ModuleName.Raw
  -- ^ Expected module name
  -> FilePath
  -- ^ Module file path
  -> File.Time
  -- ^ File modification time
  -> Details.BuildID
  -- ^ Build ID for tracking
  -> IO Status
  -- ^ File processing status result
crawlFile env@(Env _ root projectType _ buildID _ _) mvar docsNeed expectedName path time lastChange = do
  source <- File.readUtf8 (root </> path)
  parseAndValidateModule env mvar docsNeed expectedName path time source projectType buildID lastChange

-- | Crawl a module using configuration record.
--
-- Main entry point for module crawling that coordinates the discovery
-- and processing of modules. Delegates to the appropriate sub-modules
-- for specific functionality while maintaining a clean interface.
--
-- @since 0.19.1
crawlModule
  :: CrawlConfig
  -- ^ Crawling configuration
  -> ModuleName.Raw
  -- ^ Module name to crawl
  -> IO Status
  -- ^ Crawling status result
crawlModule config name = do
  let env@(Env _ root projectType srcDirs buildID locals foreigns) = config ^. crawlEnv
  let mvar = config ^. crawlMVar
  let docsNeed = config ^. crawlDocsNeed
  let baseName = ModuleName.toFilePath name
  paths <- Discovery.findModuleFile srcDirs baseName
  processFoundPaths env mvar docsNeed name paths root projectType buildID locals foreigns

-- | Process found module paths.
--
-- Handles the result of module file discovery and processes
-- the appropriate path or reports missing modules.
--
-- @since 0.19.1
processFoundPaths
  :: Env
  -> MVar StatusDict
  -> DocsNeed
  -> ModuleName.Raw
  -> [FilePath]
  -> FilePath
  -> Parse.ProjectType
  -> Details.BuildID
  -> Map.Map ModuleName.Raw Details.Local
  -> Map.Map ModuleName.Raw Details.Foreign
  -> IO Status
processFoundPaths env mvar docsNeed name paths root _projectType buildID locals foreigns =
  case paths of
    [] -> checkForeignOrNotFound name locals foreigns
    (path:_) -> do
      time <- File.getTime (root </> path)
      crawlFile env mvar docsNeed name path time buildID

-- | Check if module is foreign or not found.
--
-- @since 0.19.1
checkForeignOrNotFound
  :: ModuleName.Raw
  -> Map.Map ModuleName.Raw Details.Local
  -> Map.Map ModuleName.Raw Details.Foreign
  -> IO Status
checkForeignOrNotFound name locals foreigns
  | Map.member name locals = 
      let local = locals Map.! name
      in pure (SCached local)
  | Map.member name foreigns = 
      let (Details.Foreign pkgName _duplicates) = foreigns Map.! name
      in pure (SForeign pkgName)
  | otherwise = pure (SBadImport Import.NotFound)

-- | Parse and validate module.
--
-- @since 0.19.1
parseAndValidateModule
  :: Env
  -> MVar StatusDict
  -> DocsNeed
  -> ModuleName.Raw
  -> FilePath
  -> File.Time
  -> B.ByteString
  -> Parse.ProjectType
  -> Details.BuildID
  -> Details.BuildID
  -> IO Status
parseAndValidateModule env mvar docsNeed expectedName path time source projectType buildID lastChange =
  case Parse.fromByteString projectType source of
    Left err -> pure $ SBadSyntax path time source err
    Right (Src.Module maybeActualName _ _ imports values _ _ _ _) ->
      case maybeActualName of
        Nothing -> pure $ SBadSyntax path time source (Syntax.ModuleNameUnspecified expectedName)
        Just name@(A.At _ actualName) ->
          if expectedName == actualName
            then processValidatedModule env mvar docsNeed path time source imports values buildID lastChange
            else pure $ SBadSyntax path time source (Syntax.ModuleNameMismatch expectedName name)

-- | Process validated module.
--
-- @since 0.19.1
processValidatedModule
  :: Env
  -> MVar StatusDict
  -> DocsNeed
  -> FilePath
  -> File.Time
  -> B.ByteString
  -> [Src.Import]
  -> [A.Located Src.Value]
  -> Details.BuildID
  -> Details.BuildID
  -> IO Status
processValidatedModule env mvar docsNeed path time source imports values buildID lastChange = do
  let deps = fmap Src.getImportName imports
  let local = Details.Local path time deps (any isMainValue values) lastChange buildID
  crawlDeps env mvar deps (SChanged local source undefined docsNeed)

-- | Check if value is main function.
--
-- Identifies main function declarations in module value definitions
-- for proper module categorization and build optimization.
--
-- @since 0.19.1
isMainValue :: A.Located Src.Value -> Bool
isMainValue (A.At _ (Src.Value (A.At _ name) _ _ _)) = name == Name._main

-- | Crawl dependencies for a module.
--
-- Manages concurrent dependency crawling by coordinating with the
-- status dictionary to track which modules are already being processed
-- and ensuring all dependencies are resolved before proceeding.
--
-- @since 0.19.1
crawlDeps
  :: Env
  -- ^ Build environment
  -> MVar StatusDict
  -- ^ Status dictionary for coordination
  -> [ModuleName.Raw]
  -- ^ List of dependencies to crawl
  -> a
  -- ^ Value to return after dependencies resolved
  -> IO a
  -- ^ Result value after dependency resolution
crawlDeps env mvar deps blockedValue = do
  statusDict <- takeMVar mvar
  let depsDict = Map.fromSet (const ()) (Set.fromList deps)
  let newsDict = Map.difference depsDict statusDict
  statuses <- Map.traverseWithKey (crawlNewDep env mvar) newsDict
  putMVar mvar (Map.union statuses statusDict)
  traverse_ readMVar statuses
  pure blockedValue

-- | Crawl a new dependency.
--
-- Initiates crawling for a dependency that hasn't been processed yet
-- by forking a new thread and returning an MVar for coordination.
--
-- @since 0.19.1
crawlNewDep
  :: Env
  -- ^ Build environment  
  -> MVar StatusDict
  -- ^ Status dictionary for coordination
  -> ModuleName.Raw
  -- ^ Module name to crawl
  -> ()
  -- ^ Unit value (from Map traversal)
  -> IO (MVar Status)
  -- ^ MVar containing crawling result
crawlNewDep env mvar name () = 
  let config = CrawlConfig env mvar (DocsNeed False)
  in fork (crawlModule config name)

-- | Fork an IO operation into a new thread.
--
-- Creates a new thread for the given IO operation and returns
-- an MVar that will contain the result when the operation completes.
--
-- @since 0.19.1
fork
  :: IO a
  -- ^ IO operation to fork
  -> IO (MVar a)
  -- ^ MVar containing result when operation completes
fork work = do
  mvar <- newEmptyMVar
  _ <- forkIO $ work >>= putMVar mvar
  pure mvar