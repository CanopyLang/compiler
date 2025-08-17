{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Dependency crawling and root module handling for the Build system.
--
-- This module provides comprehensive dependency management capabilities including:
--
-- * Dependency discovery and crawling coordination
-- * Root module processing for different project entry points
-- * Concurrent dependency resolution using MVars
-- * Foreign dependency resolution and validation
--
-- The dependency system handles two main scenarios:
--
-- @
-- 1. Root Modules:
--    - Inside root: Module within project structure
--    - Outside root: External module file
--
-- 2. Dependencies:
--    - Local dependencies: Project modules
--    - Foreign dependencies: External packages
--    - Kernel dependencies: Native JavaScript modules
-- @
--
-- === Usage Examples
--
-- @
-- -- Crawl module dependencies
-- crawlDeps env mvar deps blockedValue
--
-- -- Process root module
-- rootStatus <- crawlRoot env mvar rootLocation
-- case rootStatus of
--   SInside name -> handleInsideRoot name
--   SOutsideOk local source modul -> handleOutsideRoot local
--   SOutsideErr error -> handleError error
-- @
--
-- === Concurrency Model
--
-- Dependency crawling uses MVar-based coordination to handle concurrent
-- module processing while avoiding race conditions and ensuring proper
-- dependency resolution order.
--
-- === Error Handling
--
-- Provides comprehensive error reporting for:
--   * Missing dependencies
--   * Circular dependency detection  
--   * Root module parsing failures
--   * Foreign dependency resolution issues
--
-- @since 0.19.1
module Build.Crawl.Dependencies
  ( -- * Dependency Crawling (re-exported from Core)
    module Build.Crawl.Core
    -- * Root Module Processing
  , crawlRoot
  , crawlInsideRoot
  , crawlOutsideRoot
  , parseRootModule
  ) where

import Control.Concurrent.MVar (MVar, takeMVar, putMVar, newEmptyMVar)
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.ByteString as B
import qualified File
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A
import qualified Reporting.Error as Error

import Build.Config (CrawlConfig (..))  
import Build.Types
  ( Env (..)
  , StatusDict
  , DocsNeed (..)
  , RootLocation (..)
  , RootStatus (..)
  )
import Build.Crawl.Core

-- crawlDeps and crawlNewDep are now re-exported from Build.Crawl.Core

-- | Crawl root module based on location type.
--
-- Handles different root module scenarios:
--   * Inside root: Module within the project structure
--   * Outside root: External module file provided as argument
--
-- ==== Examples
--
-- >>> crawlRoot env mvar (LInside "Main")
-- SInside "Main"
--
-- >>> crawlRoot env mvar (LOutside "Custom.elm")  
-- SOutsideOk local source modul
--
-- @since 0.19.1
crawlRoot
  :: Env
  -- ^ Build environment
  -> MVar StatusDict
  -- ^ Status dictionary for coordination
  -> RootLocation
  -- ^ Root module location specification
  -> IO RootStatus
  -- ^ Root processing status result
crawlRoot env@(Env _ _ projectType _ buildID _ _) mvar root =
  case root of
    LInside name -> crawlInsideRoot env mvar name
    LOutside path -> crawlOutsideRoot env mvar projectType path buildID

-- | Crawl inside root module.
--
-- Processes a root module that exists within the project structure
-- by adding it to the status dictionary and initiating crawling.
--
-- @since 0.19.1
crawlInsideRoot
  :: Env
  -- ^ Build environment
  -> MVar StatusDict
  -- ^ Status dictionary for coordination
  -> ModuleName.Raw
  -- ^ Root module name
  -> IO RootStatus
  -- ^ Inside root processing status
crawlInsideRoot env mvar name = do
  statusMVar <- newEmptyMVar
  statusDict <- takeMVar mvar
  putMVar mvar (Map.insert name statusMVar statusDict)
  let config = CrawlConfig env mvar (DocsNeed False)
  crawlModule config name >>= putMVar statusMVar
  pure (SInside name)

-- | Crawl outside root module.
--
-- Processes a root module from an external file by reading,
-- parsing, and validating the module source code.
--
-- @since 0.19.1
crawlOutsideRoot
  :: Env
  -- ^ Build environment
  -> MVar StatusDict
  -- ^ Status dictionary for coordination
  -> Parse.ProjectType
  -- ^ Project type for parsing context
  -> FilePath
  -- ^ Path to external root module
  -> Details.BuildID
  -- ^ Build ID for tracking
  -> IO RootStatus
  -- ^ Outside root processing status
crawlOutsideRoot env mvar projectType path buildID = do
  time <- File.getTime path
  source <- File.readUtf8 path
  parseRootModule env mvar projectType path time source buildID

-- | Parse root module source.
--
-- Parses external root module source and processes dependencies
-- or returns error information for parsing failures.
--
-- @since 0.19.1
parseRootModule
  :: Env
  -- ^ Build environment
  -> MVar StatusDict
  -- ^ Status dictionary for coordination
  -> Parse.ProjectType
  -- ^ Project type for parsing context
  -> FilePath
  -- ^ Root module file path
  -> File.Time
  -- ^ File modification time
  -> B.ByteString
  -- ^ Module source code
  -> Details.BuildID
  -- ^ Build ID for tracking
  -> IO RootStatus
  -- ^ Root module parsing status
parseRootModule env mvar projectType path time source buildID =
  case Parse.fromByteString projectType source of
    Right modul@(Src.Module _ _ _ imports values _ _ _ _) -> processRootModule env mvar path time source imports values buildID modul
    Left syntaxError -> pure . SOutsideErr $ Error.Module "???" path time source (Error.BadSyntax syntaxError)
  where
    processRootModule e m p t s imports values bID modul = do
      let deps = fmap Src.getImportName imports
      let local = Details.Local p t deps (any isMain values) bID bID
      crawlDeps e m deps (SOutsideOk local s modul)

-- fork function is now re-exported from Build.Crawl.Core

-- | Check if value is main function.
--
-- Identifies main function declarations in module value definitions
-- for proper module categorization and build optimization.
-- 
-- This is a utility function used by root module processing.
--
-- @since 0.19.1
isMain
  :: A.Located Src.Value
  -- ^ Located value declaration
  -> Bool
  -- ^ Whether value is main function
isMain (A.At _ (Src.Value (A.At _ name) _ _ _)) = name == Name._main



