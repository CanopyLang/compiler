{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
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
    -- * Module Processing
  , parseAndValidateModule
  , processValidatedModule
    -- * Utilities
  , isMainValue
  ) where

import Control.Exception (SomeException, catch)
import Control.Lens ((^.))
import Debug.Trace (trace)
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Name as Name
import qualified Data.ByteString as B
import qualified File
import qualified Data.Map.Strict as Map
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Import as Import
import qualified Reporting.Error.Syntax as Syntax
-- FilePath import removed since paths are now absolute

import Build.Config (CrawlConfig (..), crawlEnv, crawlMVar, crawlDocsNeed)
import Build.Types (Env (..), Status (..), StatusDict, DocsNeed(DocsNeed))
import qualified Build.Crawl.Discovery as Discovery

-- For dependency crawling
import Control.Concurrent (forkIO)
import Control.Concurrent.STM (TVar, atomically, readTVar, modifyTVar, newTVar, writeTVar)
import qualified Control.Concurrent.STM as STM
import qualified Data.Set as Set
import Data.Foldable (traverse_)
import qualified Data.List as List

-- =============================================================================
-- Kernel Module Filtering
-- =============================================================================

-- | Check if a module name is a kernel module.
--
-- Kernel modules should be filtered out of dependency lists as they are handled
-- specially by the compiler and don't go through normal dependency resolution.
--
-- @since 0.19.1
isKernelModule :: ModuleName.Raw -> Bool
isKernelModule moduleName =
  let moduleStr = ModuleName.toChars moduleName
  in "Elm.Kernel." `List.isPrefixOf` moduleStr || "Canopy.Kernel." `List.isPrefixOf` moduleStr

-- | Filter out kernel modules from dependency list.
--
-- Removes kernel modules from a list of module dependencies since they
-- should not go through normal dependency resolution.
--
-- @since 0.19.1
filterNonKernelDeps :: [ModuleName.Raw] -> [ModuleName.Raw]
filterNonKernelDeps = filter (not . isKernelModule)

-- =============================================================================
-- File Processing Functions
-- =============================================================================

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
  -> TVar StatusDict
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
crawlFile env@(Env _ _root projectType _ buildID _ _) mvar docsNeed expectedName path time lastChange = do
  -- FIXED: path is already absolute from Discovery.findModuleFile, don't prefix with root
  source <- File.readUtf8 path
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
  -> TVar StatusDict
  -> DocsNeed
  -> ModuleName.Raw
  -> [FilePath]
  -> FilePath
  -> Parse.ProjectType
  -> Details.BuildID
  -> Map.Map ModuleName.Raw Details.Local
  -> Map.Map ModuleName.Raw Details.Foreign
  -> IO Status
processFoundPaths env mvar docsNeed name paths _root _projectType buildID locals foreigns =
  case paths of
    [] -> checkForeignOrNotFound name locals foreigns
    (path:_) -> do
      -- FIXED: Discovery.findModuleFile returns absolute paths, don't prefix with root
      time <- File.getTime path
      crawlFile env mvar docsNeed name path time buildID

-- | Check if module is foreign or not found.
--
-- @since 0.19.1
checkForeignOrNotFound
  :: ModuleName.Raw
  -> Map.Map ModuleName.Raw Details.Local
  -> Map.Map ModuleName.Raw Details.Foreign
  -> IO Status
checkForeignOrNotFound name locals foreigns = do
  case Map.lookup name locals of
    Just local -> pure (SCached local)
    Nothing ->
      case Map.lookup name foreigns of
        Just (Details.Foreign pkgName _duplicates) -> pure (SForeign pkgName)
        Nothing -> pure (SBadImport Import.NotFound)

-- | Parse and validate module.
--
-- @since 0.19.1
parseAndValidateModule
  :: Env
  -> TVar StatusDict
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
    Right srcModule@(Src.Module maybeActualName _ _ imports _ values _ _ _ _) ->
      case maybeActualName of
        Nothing -> pure $ SBadSyntax path time source (Syntax.ModuleNameUnspecified expectedName)
        Just name@(A.At _ actualName) ->
          if expectedName == actualName
            then processValidatedModule env mvar docsNeed path time source srcModule imports values buildID lastChange
            else pure $ SBadSyntax path time source (Syntax.ModuleNameMismatch expectedName name)

-- | Process validated module.
--
-- @since 0.19.1
processValidatedModule
  :: Env
  -> TVar StatusDict
  -> DocsNeed
  -> FilePath
  -> File.Time
  -> B.ByteString
  -> Src.Module
  -> [Src.Import]
  -> [A.Located Src.Value]
  -> Details.BuildID
  -> Details.BuildID
  -> IO Status
processValidatedModule env mvar docsNeed path time source srcModule imports values buildID lastChange = do
  let allDeps = fmap Src.getImportName imports
  let deps = filterNonKernelDeps allDeps
  let local = Details.Local path time deps (any isMainValue values) lastChange buildID
  crawlDeps env mvar deps (SChanged local source srcModule docsNeed)

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
-- FIXED: Uses proper concurrent pattern to avoid MVar deadlock.
-- Previously used take-modify-put anti-pattern which caused circular dependencies.
--
-- @since 0.19.1
crawlDeps
  :: Env
  -- ^ Build environment
  -> TVar StatusDict
  -- ^ Status dictionary for coordination
  -> [ModuleName.Raw]
  -- ^ List of dependencies to crawl
  -> a
  -- ^ Value to return after dependencies resolved
  -> IO a
  -- ^ Result value after dependency resolution
crawlDeps env mvar deps blockedValue = do
  -- FIXED: Use STM to atomically determine new dependencies
  newTVars <- atomically $ do
    statusDict <- readTVar mvar
    let depsDict = Map.fromSet (const ()) (Set.fromList deps)
    let newsDict = Map.difference depsDict statusDict
    -- Create TVars for new dependencies inside STM
    newTVars <- Map.traverseWithKey (\_ () -> newTVar (SBadImport Import.NotFound)) newsDict
    -- Update status dict with the new TVars
    modifyTVar mvar (Map.union newTVars)
    pure newTVars

  -- Now start crawling the new dependencies
  traverse_ (startCrawling env mvar) (Map.toList newTVars)

  -- Wait for all dependencies to complete
  traverse_ waitForStatusResult newTVars
  pure blockedValue
  where
    startCrawling :: Env -> TVar StatusDict -> (ModuleName.Raw, TVar Status) -> IO ()
    startCrawling env' _statusTVar (name, resultTVar) = do
      let config = CrawlConfig env' mvar (DocsNeed False)
      _ <- forkIO $ do
        -- FIXED: Handle exceptions to prevent TVar deadlock
        -- Always put a result to the TVar, even if crawling fails
        result <- (crawlModule config name) `catch` \(e :: SomeException) -> do
          -- Log the exception but return a failure status
          putStrLn $ "WARNING: Exception in crawlModule for " ++ show name ++ ": " ++ show e
          -- Use zero time for error case
          let errorTime = File.Time 0
          pure (SBadSyntax "error" errorTime B.empty (error ("Exception in crawlModule: " ++ show e)))
        atomically $ writeTVar resultTVar result
      pure ()

-- | Wait for a Status TVar that may initially contain a placeholder error value
waitForStatusResult :: TVar Status -> IO Status
waitForStatusResult tvar = do
  STM.atomically $ do
    status <- STM.readTVar tvar
    case status of
      SBadImport Import.NotFound -> trace ("STM-RETRY: Build.Crawl.Core - waiting for real result, got placeholder NotFound") STM.retry
      _ -> pure status  -- Return any other status

-- NOTE: crawlNewDep function removed - functionality integrated into fixed crawlDeps

-- NOTE: fork function removed - use TVar-based fork from Build.Orchestration.Workflow