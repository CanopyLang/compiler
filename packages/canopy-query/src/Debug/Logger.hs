{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Comprehensive debug logging system for the new query-based compiler.
--
-- This module provides strongly-typed debug categories and environment-based
-- filtering. Use CANOPY_DEBUG=1 to enable all categories, or CANOPY_DEBUG=PARSE,TYPE
-- to enable specific categories.
--
-- == Usage Examples
--
-- @
-- import qualified New.Compiler.Debug.Logger as Logger
-- import New.Compiler.Debug.Logger (DebugCategory(..))
--
-- parseModule :: FilePath -> IO Module
-- parseModule path = do
--   Logger.debug PARSE ("Parsing module: " ++ path)
--   -- ... parsing logic
--   Logger.debug PARSE ("Parse complete")
-- @
--
-- @since 0.19.1
module Debug.Logger
  ( -- * Debug Categories
    DebugCategory (..),

    -- * Debug Functions
    debug,
    debugIO,
    isDebugEnabled,
    enabledCategories,

    -- * Category Predicates
    shouldLog,
  )
where

import qualified Data.List as List
import qualified Data.Text as Text
import Data.Text (Text)
import qualified System.Environment as Env
import System.IO.Unsafe (unsafePerformIO)

-- | Debug categories for compiler phases.
--
-- Each category represents a distinct compilation phase or subsystem.
-- Categories can be selectively enabled via the CANOPY_DEBUG environment variable.
--
-- @since 0.19.1
data DebugCategory
  = PARSE -- ^ Parsing operations
  | TYPE -- ^ Type checking and inference
  | CODEGEN -- ^ Code generation
  | BUILD -- ^ Build system operations
  | COMPILE_DEBUG -- ^ General compilation
  | DEPS_SOLVER -- ^ Dependency resolution
  | CACHE_DEBUG -- ^ Cache operations
  | QUERY_DEBUG -- ^ Query execution
  | WORKER_DEBUG -- ^ Worker pool operations
  | KERNEL_DEBUG -- ^ Kernel code handling
  | FFI_DEBUG -- ^ FFI processing
  | PERMISSIONS_DEBUG -- ^ Permission validation
  deriving (Show, Eq, Ord)

-- | Get enabled debug categories from environment.
--
-- Reads the CANOPY_DEBUG environment variable:
--   * "1" or "true" - Enable all categories
--   * "PARSE,TYPE" - Enable specific categories (comma-separated)
--   * Not set - Disable all debugging
--
-- @since 0.19.1
{-# NOINLINE enabledCategories #-}
enabledCategories :: [DebugCategory]
enabledCategories = unsafePerformIO $ do
  maybeDebug <- Env.lookupEnv "CANOPY_DEBUG"
  case maybeDebug of
    Nothing -> return []
    Just "1" -> return allCategories
    Just "true" -> return allCategories
    Just value -> return (parseCategories value)
  where
    allCategories =
      [ PARSE,
        TYPE,
        CODEGEN,
        BUILD,
        COMPILE_DEBUG,
        DEPS_SOLVER,
        CACHE_DEBUG,
        QUERY_DEBUG,
        WORKER_DEBUG,
        KERNEL_DEBUG,
        FFI_DEBUG,
        PERMISSIONS_DEBUG
      ]

-- | Parse comma-separated category names.
parseCategories :: String -> [DebugCategory]
parseCategories value =
  let names = Text.splitOn "," (Text.pack value)
   in concatMap parseCategory names

-- | Parse a single category name.
parseCategory :: Text -> [DebugCategory]
parseCategory name =
  case Text.strip name of
    "PARSE" -> [PARSE]
    "TYPE" -> [TYPE]
    "CODEGEN" -> [CODEGEN]
    "BUILD" -> [BUILD]
    "COMPILE_DEBUG" -> [COMPILE_DEBUG]
    "DEPS_SOLVER" -> [DEPS_SOLVER]
    "CACHE_DEBUG" -> [CACHE_DEBUG]
    "QUERY_DEBUG" -> [QUERY_DEBUG]
    "WORKER_DEBUG" -> [WORKER_DEBUG]
    "KERNEL_DEBUG" -> [KERNEL_DEBUG]
    "FFI_DEBUG" -> [FFI_DEBUG]
    "PERMISSIONS_DEBUG" -> [PERMISSIONS_DEBUG]
    _ -> []

-- | Check if debugging is enabled.
isDebugEnabled :: Bool
isDebugEnabled = not (List.null enabledCategories)

-- | Check if a category should be logged.
shouldLog :: DebugCategory -> Bool
shouldLog category = category `elem` enabledCategories

-- | Log a debug message for a category.
--
-- Only logs if the category is enabled via CANOPY_DEBUG.
--
-- @since 0.19.1
debug :: DebugCategory -> String -> IO ()
debug category message
  | shouldLog category = putStrLn formatted
  | otherwise = return ()
  where
    formatted = "[" ++ show category ++ "] " ++ message

-- | Log a debug message in IO context.
debugIO :: DebugCategory -> IO String -> IO ()
debugIO category action
  | shouldLog category = action >>= debug category
  | otherwise = return ()
