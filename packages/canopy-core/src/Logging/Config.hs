{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Configuration for the Canopy structured logging system.
--
-- Reads environment variables to determine log level, phase filtering,
-- and output format. The configuration is cached in an 'IORef' via
-- 'unsafePerformIO' for zero-overhead repeated reads.
--
-- == Environment Variables
--
-- * @CANOPY_LOG=1@ — Enable all phases at INFO level
-- * @CANOPY_LOG=DEBUG@ — Enable all phases at DEBUG level
-- * @CANOPY_LOG=DEBUG:TYPE,PARSE@ — Enable specific phases at DEBUG
-- * @CANOPY_LOG_LEVEL=TRACE@ — Override the minimum log level
-- * @CANOPY_LOG_FORMAT=json@ — Switch to NDJSON output (default: cli)
-- * @CANOPY_LOG_FILE=/tmp/canopy.log@ — Also write events to a file
--
-- @since 0.19.1
module Logging.Config
  ( LogConfig (..),
    OutputFormat (..),
    readConfig,
    shouldEmit,
  )
where

import Data.IORef (IORef)
import qualified Data.IORef as IORef
import Data.Text (Text)
import qualified Data.Text as Text
import Logging.Event (LogEvent, LogLevel (..), Phase (..))
import qualified Logging.Event as Event
import qualified System.Environment as Env
import System.IO.Unsafe (unsafePerformIO)

-- | Output format for log events.
--
-- @since 0.19.1
data OutputFormat
  = FormatCLI
  | FormatJSON
  deriving (Show, Eq)

-- | Immutable logging configuration parsed from environment variables.
--
-- @since 0.19.1
data LogConfig = LogConfig
  { _configEnabled :: !Bool,
    _configLevel :: !LogLevel,
    _configPhases :: ![Phase],
    _configFormat :: !OutputFormat,
    _configFile :: !(Maybe FilePath)
  }
  deriving (Show, Eq)

-- | Cached configuration. Initialized once from environment on first access.
{-# NOINLINE configRef #-}
configRef :: IORef LogConfig
configRef = unsafePerformIO (parseConfig >>= IORef.newIORef)

-- | Read the cached logging configuration.
readConfig :: IO LogConfig
readConfig = IORef.readIORef configRef

-- | Decide whether an event should be emitted under the current configuration.
shouldEmit :: LogConfig -> LogEvent -> Bool
shouldEmit cfg evt =
  _configEnabled cfg
    && Event.eventLevel evt >= _configLevel cfg
    && phaseAllowed (_configPhases cfg) (Event.eventPhase evt)
  where
    phaseAllowed [] _ = True
    phaseAllowed ps p = p `elem` ps

-- | Parse all environment variables into a 'LogConfig'.
parseConfig :: IO LogConfig
parseConfig = do
  canopyLog <- Env.lookupEnv "CANOPY_LOG"
  canopyLevel <- Env.lookupEnv "CANOPY_LOG_LEVEL"
  canopyFormat <- Env.lookupEnv "CANOPY_LOG_FORMAT"
  canopyFile <- Env.lookupEnv "CANOPY_LOG_FILE"

  let fmt = parseFormat canopyFormat
  let file = canopyFile

  case canopyLog of
    Nothing ->
      pure (LogConfig False INFO [] fmt file)
    Just "0" ->
      pure (LogConfig False INFO [] fmt file)
    Just "1" ->
      pure (LogConfig True (overrideLevel canopyLevel INFO) [] fmt file)
    Just value -> do
      let (level, phases) = parseLogValue value
      let finalLevel = overrideLevel canopyLevel level
      pure (LogConfig True finalLevel phases fmt file)

-- | Parse the @CANOPY_LOG@ value into a level and optional phase list.
--
-- Accepted forms:
--   * @"DEBUG"@ — level only, all phases
--   * @"DEBUG:TYPE,PARSE"@ — level with specific phases
--   * @"1"@ / @"2"@ / @"3"@ — numeric shorthand
parseLogValue :: String -> (LogLevel, [Phase])
parseLogValue value =
  case break (== ':') value of
    (levelStr, ':' : phaseStr) ->
      (parseLevel levelStr, parsePhases phaseStr)
    (levelStr, _) ->
      (parseLevel levelStr, [])

-- | Parse a level string. Accepts names and numeric shorthands.
parseLevel :: String -> LogLevel
parseLevel str =
  case fmap toUpper str of
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

-- | Override level with @CANOPY_LOG_LEVEL@ if set.
overrideLevel :: Maybe String -> LogLevel -> LogLevel
overrideLevel Nothing fallback = fallback
overrideLevel (Just s) _ = parseLevel s

-- | Parse the output format from @CANOPY_LOG_FORMAT@.
parseFormat :: Maybe String -> OutputFormat
parseFormat Nothing = FormatCLI
parseFormat (Just s) =
  case Text.toLower (Text.pack s) of
    "json" -> FormatJSON
    "ndjson" -> FormatJSON
    _ -> FormatCLI

-- | Parse comma-separated phase names.
parsePhases :: String -> [Phase]
parsePhases value =
  concatMap parseOnePhase (Text.splitOn "," (Text.pack value))

-- | Parse a single phase name to a list (empty on unrecognized input).
parseOnePhase :: Text -> [Phase]
parseOnePhase raw =
  case Text.strip (Text.toUpper raw) of
    "PARSE" -> [PhaseParse]
    "CANON" -> [PhaseCanon]
    "CANONICALIZE" -> [PhaseCanon]
    "TYPE" -> [PhaseType]
    "OPT" -> [PhaseOptimize]
    "OPTIMIZE" -> [PhaseOptimize]
    "GEN" -> [PhaseGenerate]
    "GENERATE" -> [PhaseGenerate]
    "BUILD" -> [PhaseBuild]
    "CACHE" -> [PhaseCache]
    "FFI" -> [PhaseFFI]
    "WORKER" -> [PhaseWorker]
    "KERNEL" -> [PhaseKernel]
    "PKG" -> [PhasePackage]
    "PACKAGE" -> [PhasePackage]
    "ALL" -> allPhases
    _ -> []

-- | All known phases for the @ALL@ shorthand.
allPhases :: [Phase]
allPhases =
  [ PhaseParse,
    PhaseCanon,
    PhaseType,
    PhaseOptimize,
    PhaseGenerate,
    PhaseBuild,
    PhaseCache,
    PhaseFFI,
    PhaseWorker,
    PhaseKernel,
    PhasePackage
  ]
