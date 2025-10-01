{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Comprehensive production-grade logging system for Canopy compiler.
--
-- This module provides a zero-cost logging abstraction with:
--   * Five log levels: TRACE, DEBUG, INFO, WARN, ERROR
--   * Component-based filtering via debug categories
--   * Environment variable configuration
--   * Structured output with timestamps
--   * Zero performance impact when disabled
--
-- == Configuration
--
-- Environment variables:
--   * @CANOPY_LOG=1@ - Enable all categories at INFO level
--   * @CANOPY_LOG=DEBUG@ - Enable all categories at DEBUG level
--   * @CANOPY_LOG=DEBUG:PARSE,TYPE@ - Enable specific components at DEBUG
--   * @CANOPY_LOG_LEVEL=TRACE@ - Set global minimum log level
--
-- == Usage Examples
--
-- @
-- import qualified Logging.Debug as Log
-- import Logging.Debug (DebugCategory(..))
--
-- buildModule :: FilePath -> IO ()
-- buildModule path = do
--   Log.info BUILD ("Building module: " ++ path)
--   Log.debug BUILD "Starting dependency resolution"
--   result <- resolveDeps path
--   case result of
--     Left err -> Log.errorMsg BUILD ("Failed: " ++ show err)
--     Right _ -> Log.info BUILD "Build complete"
-- @
--
-- @since 0.19.1
module Logging.Debug
  ( -- * Log Levels
    LogLevel (..),

    -- * Debug Categories
    DebugCategory (..),

    -- * Logging Functions
    trace,
    debug,
    info,
    warn,
    errorMsg,

    -- * Configuration
    isLoggingEnabled,
    enabledCategories,
    minimumLogLevel,
    shouldLog,

    -- * Legacy Compatibility
    printLog,
    setLogFlag,
  )
where

import qualified Data.List as List
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Time.Clock as Time
import qualified Data.Time.Format as TimeFormat
import qualified System.Environment as Env
import System.IO.Unsafe (unsafePerformIO)

-- | Log severity levels.
--
-- Ordered from most verbose (TRACE) to least verbose (ERROR).
--
-- @since 0.19.1
data LogLevel
  = TRACE -- ^ Very verbose: function entry/exit, detailed state
  | DEBUG -- ^ Development: algorithm steps, intermediate results
  | INFO -- ^ Production: high-level progress, milestones
  | WARN -- ^ Warnings: non-fatal issues, deprecations
  | ERROR -- ^ Errors: failures requiring attention
  deriving (Show, Eq, Ord)

-- | Debug categories for compiler phases and subsystems.
--
-- Each category represents a distinct compilation phase or subsystem.
-- Categories can be selectively enabled via environment variables.
--
-- @since 0.19.1
data DebugCategory
  = PARSE -- ^ Parsing operations
  | TYPE -- ^ Type checking and inference
  | CODEGEN -- ^ Code generation
  | BUILD -- ^ Build system operations
  | COMPILE -- ^ General compilation
  | DEPS_SOLVER -- ^ Dependency resolution
  | CACHE -- ^ Cache operations
  | QUERY -- ^ Query execution
  | WORKER -- ^ Worker pool operations
  | KERNEL -- ^ Kernel code handling
  | FFI -- ^ FFI processing
  | PERMISSIONS -- ^ Permission validation
  | DRIVER -- ^ NEW Driver operations
  | BOOTSTRAP -- ^ Bootstrap compilation
  deriving (Show, Eq, Ord)

-- | Configuration parsed from environment variables.
data LogConfig = LogConfig
  { configLevel :: !LogLevel,
    configCategories :: ![DebugCategory],
    configEnabled :: !Bool
  }

-- | Get logging configuration from environment.
--
-- Parses CANOPY_LOG and CANOPY_LOG_LEVEL environment variables.
--
-- @since 0.19.1
{-# NOINLINE logConfig #-}
logConfig :: LogConfig
logConfig = unsafePerformIO parseLogConfig

-- | Parse environment variables into configuration.
parseLogConfig :: IO LogConfig
parseLogConfig = do
  maybeLog <- Env.lookupEnv "CANOPY_LOG"
  maybeLevel <- Env.lookupEnv "CANOPY_LOG_LEVEL"

  let defaultLevel = INFO
  let globalLevel = maybe defaultLevel parseLevel maybeLevel

  case maybeLog of
    Nothing -> return (LogConfig globalLevel [] False)
    Just "0" -> return (LogConfig globalLevel [] False)
    Just "1" -> return (LogConfig globalLevel allCategories True)
    Just value -> do
      let (level, cats) = parseLogValue value
      let finalLevel = if maybeLevel == Nothing then level else globalLevel
      return (LogConfig finalLevel cats True)

-- | Parse CANOPY_LOG value (e.g., "DEBUG:PARSE,TYPE").
parseLogValue :: String -> (LogLevel, [DebugCategory])
parseLogValue value =
  case break (== ':') value of
    (levelStr, ':' : catStr) ->
      (parseLevel levelStr, parseCategories catStr)
    (levelStr, _) ->
      case parseLevel levelStr of
        level | level == INFO -> (level, allCategories)
        level -> (level, allCategories)

-- | Parse log level from string.
parseLevel :: String -> LogLevel
parseLevel str =
  case map toUpper str of
    "TRACE" -> TRACE
    "DEBUG" -> DEBUG
    "INFO" -> INFO
    "WARN" -> WARN
    "WARNING" -> WARN
    "ERROR" -> ERROR
    "1" -> INFO
    "2" -> DEBUG
    "3" -> TRACE
    _ -> INFO
  where
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise = c

-- | All available debug categories.
allCategories :: [DebugCategory]
allCategories =
  [ PARSE,
    TYPE,
    CODEGEN,
    BUILD,
    COMPILE,
    DEPS_SOLVER,
    CACHE,
    QUERY,
    WORKER,
    KERNEL,
    FFI,
    PERMISSIONS,
    DRIVER,
    BOOTSTRAP
  ]

-- | Parse comma-separated category names.
parseCategories :: String -> [DebugCategory]
parseCategories value =
  let names = Text.splitOn "," (Text.pack value)
   in concatMap parseCategory names

-- | Parse a single category name.
parseCategory :: Text -> [DebugCategory]
parseCategory name =
  case Text.strip (Text.toUpper name) of
    "PARSE" -> [PARSE]
    "TYPE" -> [TYPE]
    "CODEGEN" -> [CODEGEN]
    "BUILD" -> [BUILD]
    "COMPILE" -> [COMPILE]
    "DEPS_SOLVER" -> [DEPS_SOLVER]
    "DEPS" -> [DEPS_SOLVER]
    "CACHE" -> [CACHE]
    "QUERY" -> [QUERY]
    "WORKER" -> [WORKER]
    "KERNEL" -> [KERNEL]
    "FFI" -> [FFI]
    "PERMISSIONS" -> [PERMISSIONS]
    "DRIVER" -> [DRIVER]
    "BOOTSTRAP" -> [BOOTSTRAP]
    "ALL" -> allCategories
    _ -> []

-- | Check if logging is enabled globally.
isLoggingEnabled :: Bool
isLoggingEnabled = configEnabled logConfig

-- | Get currently enabled categories.
enabledCategories :: [DebugCategory]
enabledCategories = configCategories logConfig

-- | Get minimum log level.
minimumLogLevel :: LogLevel
minimumLogLevel = configLevel logConfig

-- | Check if a message should be logged.
--
-- Returns True if both:
--   1. The log level meets the minimum threshold
--   2. The category is enabled (or all categories are enabled)
shouldLog :: LogLevel -> DebugCategory -> Bool
shouldLog level category =
  configEnabled logConfig
    && level >= minimumLogLevel
    && (List.null (configCategories logConfig) || category `elem` configCategories logConfig)

-- | Format a log message with timestamp and metadata.
formatLogMessage :: LogLevel -> DebugCategory -> String -> String
formatLogMessage level category message =
  "[" ++ timestamp ++ "] [" ++ show level ++ "] [" ++ show category ++ "] " ++ message
  where
    timestamp = unsafePerformIO getCurrentTimestamp

-- | Get current timestamp as formatted string.
getCurrentTimestamp :: IO String
getCurrentTimestamp = do
  now <- Time.getCurrentTime
  return (TimeFormat.formatTime TimeFormat.defaultTimeLocale "%Y-%m-%d %H:%M:%S" now)

-- | Log a TRACE message.
--
-- Very verbose logging for detailed debugging (function entry/exit, state dumps).
--
-- @since 0.19.1
trace :: DebugCategory -> String -> IO ()
trace category message
  | shouldLog TRACE category = putStrLn (formatLogMessage TRACE category message)
  | otherwise = return ()

-- | Log a DEBUG message.
--
-- Development-time logging for algorithm steps and intermediate results.
--
-- @since 0.19.1
debug :: DebugCategory -> String -> IO ()
debug category message
  | shouldLog DEBUG category = putStrLn (formatLogMessage DEBUG category message)
  | otherwise = return ()

-- | Log an INFO message.
--
-- Production logging for high-level progress and milestones.
--
-- @since 0.19.1
info :: DebugCategory -> String -> IO ()
info category message
  | shouldLog INFO category = putStrLn (formatLogMessage INFO category message)
  | otherwise = return ()

-- | Log a WARN message.
--
-- Warnings for non-fatal issues and deprecated usage.
--
-- @since 0.19.1
warn :: DebugCategory -> String -> IO ()
warn category message
  | shouldLog WARN category = putStrLn (formatLogMessage WARN category message)
  | otherwise = return ()

-- | Log an ERROR message.
--
-- Errors for failures requiring attention.
--
-- @since 0.19.1
errorMsg :: DebugCategory -> String -> IO ()
errorMsg category message
  | shouldLog ERROR category = putStrLn (formatLogMessage ERROR category message)
  | otherwise = return ()

-- ** Legacy Compatibility

-- | Legacy printLog function for backward compatibility.
--
-- Deprecated: Use appropriate log level functions instead.
--
-- @since 0.19.1
printLog :: String -> IO ()
printLog message
  | isLoggingEnabled = putStrLn ("[LEGACY] " ++ message)
  | otherwise = return ()

-- | Legacy setLogFlag function for backward compatibility.
--
-- Deprecated: Use CANOPY_LOG environment variable instead.
--
-- @since 0.19.1
setLogFlag :: Bool -> IO ()
setLogFlag _flag = return () -- No-op, configuration is environment-based
