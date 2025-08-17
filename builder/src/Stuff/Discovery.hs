{-# OPTIONS_GHC -Wall #-}

-- | Project root discovery and navigation for Canopy compiler.
--
-- This module provides functionality for automatically detecting Canopy and Elm
-- project roots within directory hierarchies. It performs upward traversal from
-- the current working directory to locate project configuration files and
-- establish the project context for build operations.
--
-- The discovery system supports both Canopy (.canopy.json) and Elm (elm.json)
-- project configurations, enabling seamless migration and compatibility between
-- the two compilers.
--
-- == Key Features
--
-- * **Automatic Project Detection** - Finds project roots without manual configuration
-- * **Multi-Format Support** - Recognizes both canopy.json and elm.json files
-- * **Upward Traversal** - Searches parent directories until project found or filesystem root reached
-- * **Robust Error Handling** - Graceful handling of permission errors and missing files
-- * **Performance Optimized** - Efficient directory traversal with early termination
--
-- == Discovery Algorithm
--
-- The project discovery follows a systematic approach:
--
-- 1. **Start Location** - Begin at current working directory
-- 2. **Configuration Check** - Look for canopy.json or elm.json in current directory
-- 3. **Success Termination** - Return directory path if configuration found
-- 4. **Upward Movement** - Move to parent directory if no configuration found
-- 5. **Root Termination** - Return Nothing if filesystem root reached without finding project
--
-- == Supported Project Files
--
-- * **canopy.json** - Native Canopy project configuration
-- * **elm.json** - Elm project configuration (for compatibility)
--
-- Both file types are treated equally for project root detection, enabling
-- gradual migration from Elm to Canopy projects.
--
-- == Usage Examples
--
-- === Basic Project Discovery
--
-- @
-- -- Find project root from current directory
-- maybeRoot <- findRoot
-- case maybeRoot of
--   Just root -> do
--     putStrLn $ "Found project at: " ++ root
--     buildProject root
--   Nothing -> putStrLn "No Canopy/Elm project found"
-- @
--
-- === Project-Aware Operations
--
-- @
-- -- Perform operations within project context
-- withProjectRoot $ \root -> do
--   let artifactsPath = Paths.stuff root
--   initializeArtifacts artifactsPath
--   compileProject root
--   
-- withProjectRoot :: (FilePath -> IO a) -> IO (Maybe a)
-- withProjectRoot action = do
--   maybeRoot <- findRoot
--   case maybeRoot of
--     Just root -> Just <$> action root
--     Nothing -> pure Nothing
-- @
--
-- === Directory Context Validation
--
-- @
-- -- Verify current directory is within a project
-- isInProject :: IO Bool
-- isInProject = isJust <$> findRoot
--
-- -- Get project root or fail with error
-- requireProjectRoot :: IO FilePath
-- requireProjectRoot = do
--   maybeRoot <- findRoot
--   case maybeRoot of
--     Just root -> pure root
--     Nothing -> error "Not in a Canopy or Elm project directory"
-- @
--
-- == Error Conditions
--
-- The discovery process handles various error conditions gracefully:
--
-- * **Permission Errors** - Directories with insufficient read permissions are skipped
-- * **Missing Directories** - Non-existent directories in path are handled safely
-- * **Filesystem Boundaries** - Discovery stops at filesystem root without errors
-- * **Invalid Paths** - Malformed paths are detected and cause graceful failure
--
-- == Performance Characteristics
--
-- * **Time Complexity** - O(d) where d is directory tree depth
-- * **Space Complexity** - O(d) for directory path storage during traversal
-- * **I/O Operations** - Minimized through early termination and efficient checks
-- * **Caching** - No caching implemented (discovery is fast enough for repeated calls)
--
-- The module prioritizes correctness over performance, but the search algorithm
-- is efficient enough for typical project structures and development workflows.
--
-- == Thread Safety
--
-- All discovery functions are thread-safe as they only perform read operations
-- on the filesystem and maintain no shared state. Multiple threads can safely
-- call discovery functions concurrently.
--
-- @since 0.19.1
module Stuff.Discovery
  ( -- * Project Root Discovery
    findRoot
  , findRootFrom
  , findRootHelp
  ) where

import qualified Data.List as List
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import System.FilePath ((</>))
import Prelude (FilePath, IO, Maybe (..), String, return, (||))

-- | Find the root directory of a Canopy or Elm project.
--
-- Searches upward from the current working directory to find a directory
-- containing either "canopy.json" or "elm.json" configuration files.
-- This function is used to automatically detect the project root for
-- build operations and artifact storage.
--
-- The search process:
--
-- 1. **Start from current directory** - Begin search at working directory
-- 2. **Check for config files** - Look for canopy.json or elm.json
-- 3. **Traverse upward** - Move to parent directory if not found
-- 4. **Terminate at filesystem root** - Return Nothing if no project found
--
-- ==== Examples
--
-- >>> -- In /home/user/myproject/src/
-- >>> findRoot
-- Just "/home/user/myproject"
--
-- >>> -- In /tmp (no project)
-- >>> findRoot
-- Nothing
--
-- ==== Error Conditions
--
-- Returns 'Nothing' when:
--
-- * No canopy.json or elm.json found in directory tree
-- * Insufficient permissions to read directories
-- * Filesystem traversal reaches root without finding project
--
-- @since 0.19.1
findRoot :: IO (Maybe FilePath)
findRoot = do
  dir <- Dir.getCurrentDirectory
  findRootHelp (FP.splitDirectories dir)

-- | Find the root directory of a Canopy or Elm project starting from a specific directory.
--
-- Searches upward from the given directory to find a directory containing either
-- "canopy.json" or "elm.json" configuration files. This function provides thread-safe
-- project discovery that doesn't depend on the current working directory.
--
-- The search process:
--
-- 1. **Start from given directory** - Begin search at specified directory
-- 2. **Check for config files** - Look for canopy.json or elm.json
-- 3. **Traverse upward** - Move to parent directory if not found
-- 4. **Terminate at filesystem root** - Return Nothing if no project found
--
-- ==== Examples
--
-- >>> findRootFrom "/home/user/myproject/src"
-- Just "/home/user/myproject"
--
-- >>> findRootFrom "/tmp"
-- Nothing
--
-- ==== Error Conditions
--
-- Returns 'Nothing' when:
--
-- * No canopy.json or elm.json found in directory tree
-- * Insufficient permissions to read directories
-- * Filesystem traversal reaches root without finding project
-- * Starting directory does not exist
--
-- @since 0.19.1
findRootFrom :: FilePath -> IO (Maybe FilePath)
findRootFrom startDir = findRootHelp (FP.splitDirectories startDir)

-- | Helper function for project root discovery.
--
-- Recursively searches directory tree upward for project configuration
-- files. Takes a list of directory components and checks each level
-- for the presence of canopy.json or elm.json files.
--
-- The function performs these steps for each directory level:
--
-- 1. **Directory Assembly** - Reconstruct full path from components
-- 2. **Configuration Check** - Test for existence of canopy.json and elm.json
-- 3. **Success Return** - Return directory path if either file found
-- 4. **Recursive Search** - Continue with parent directory if no config found
-- 5. **Base Case** - Return Nothing when no more directories to check
--
-- ==== Algorithm Details
--
-- The search uses directory path components rather than string manipulation
-- to ensure proper handling of filesystem boundaries and path separators
-- across different operating systems.
--
-- Directory traversal stops when:
-- * Configuration file found (success)
-- * Empty directory list reached (failure)
-- * Filesystem root encountered (failure)
--
-- ==== Examples
--
-- >>> findRootHelp ["/", "home", "user", "project", "src"]
-- Just "/home/user/project"  -- if project/canopy.json exists
--
-- >>> findRootHelp ["/", "tmp", "scratch"]
-- Nothing  -- if no configuration files found
--
-- ==== Error Conditions
--
-- The function handles errors gracefully:
--
-- * **Permission Errors** - Silently skipped during file existence checks
-- * **Invalid Paths** - Malformed paths cause existence check to fail safely
-- * **Missing Directories** - Non-existent paths return False from existence check
--
-- @since 0.19.1
findRootHelp :: [String] -> IO (Maybe FilePath)
findRootHelp dirs =
  case dirs of
    [] ->
      return Nothing
    _ : _ -> do
      canopyExists <- Dir.doesFileExist (FP.joinPath dirs </> "canopy.json")
      elmExists <- Dir.doesFileExist (FP.joinPath dirs </> "elm.json")
      if canopyExists || elmExists
        then return (Just (FP.joinPath dirs))
        else findRootHelp (List.init dirs)