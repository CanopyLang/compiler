{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Output sinks for the Canopy structured logging system.
--
-- A 'Sink' is a function @LogEvent -> IO ()@ that writes an event to some
-- destination. This module provides CLI (colored, human-readable), JSON
-- (NDJSON), and file sinks, plus combinators for composing them.
--
-- @since 0.19.1
module Logging.Sink
  ( Sink (..),
    cliSink,
    jsonSink,
    fileSink,
    nullSink,
    combineSinks,
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Data.Time.Clock as Time
import qualified Data.Time.Format as TimeFormat
import Logging.Event (LogEvent, LogLevel (..))
import qualified Logging.Event as Event
import qualified System.IO as IO

-- | A sink consumes log events and writes them somewhere.
--
-- @since 0.19.1
newtype Sink = Sink {runSink :: LogEvent -> IO ()}

-- | A sink that discards all events.
nullSink :: Sink
nullSink = Sink (\_ -> pure ())

-- | Combine multiple sinks into one that writes to all of them.
combineSinks :: [Sink] -> Sink
combineSinks sinks = Sink (\evt -> mapM_ (\s -> runSink s evt) sinks)

-- | A CLI sink that writes colored, human-readable lines to a handle.
--
-- Format: @[HH:MM:SS] [LEVEL] [PHASE] message@
cliSink :: IO.Handle -> Sink
cliSink handle = Sink (writeCLI handle)

-- | Write a single event in CLI format.
writeCLI :: IO.Handle -> LogEvent -> IO ()
writeCLI handle evt = do
  ts <- currentTimestamp
  let line =
        "[" <> ts <> "] "
          <> colorLevel level ("[" <> Event.renderLevel level <> "]")
          <> " ["
          <> Event.renderPhase (Event.eventPhase evt)
          <> "] "
          <> Event.renderCLI evt
  TextIO.hPutStrLn handle line
  IO.hFlush handle
  where
    level = Event.eventLevel evt

-- | Apply ANSI color codes based on log level.
colorLevel :: LogLevel -> Text -> Text
colorLevel level txt =
  case level of
    TRACE -> "\ESC[90m" <> txt <> "\ESC[0m"
    DEBUG -> "\ESC[36m" <> txt <> "\ESC[0m"
    INFO -> "\ESC[32m" <> txt <> "\ESC[0m"
    WARN -> "\ESC[33m" <> txt <> "\ESC[0m"
    ERROR -> "\ESC[31m" <> txt <> "\ESC[0m"

-- | A JSON sink that writes NDJSON (one JSON object per line) to a handle.
--
-- The JSON format includes: timestamp, level, phase, event type, and payload.
jsonSink :: IO.Handle -> Sink
jsonSink handle = Sink (writeJSON handle)

-- | Write a single event as a JSON line.
writeJSON :: IO.Handle -> LogEvent -> IO ()
writeJSON handle evt = do
  ts <- currentTimestamp
  let level = Event.eventLevel evt
  let phase = Event.eventPhase evt
  let msg = Event.renderCLI evt
  let line = jsonObject
        [ ("ts", jsonString ts)
        , ("level", jsonString (Event.renderLevel level))
        , ("phase", jsonString (Event.renderPhase phase))
        , ("event", jsonString (eventTypeName evt))
        , ("msg", jsonString msg)
        ]
  TextIO.hPutStrLn handle line
  IO.hFlush handle

-- | A file sink that appends events in CLI format to a file path.
fileSink :: FilePath -> IO Sink
fileSink path = do
  handle <- IO.openFile path IO.AppendMode
  IO.hSetBuffering handle IO.LineBuffering
  pure (cliSink handle)

-- | Get the current time as @HH:MM:SS.mmm@.
currentTimestamp :: IO Text
currentTimestamp = do
  now <- Time.getCurrentTime
  pure (Text.pack (TimeFormat.formatTime TimeFormat.defaultTimeLocale "%H:%M:%S%Q" now))

-- | Extract a short event type name for JSON output.
eventTypeName :: LogEvent -> Text
eventTypeName = \case
  Event.ParseStarted {} -> "parse_started"
  Event.ParseCompleted {} -> "parse_completed"
  Event.ParseFailed {} -> "parse_failed"
  Event.CanonStarted {} -> "canon_started"
  Event.CanonVarResolved {} -> "canon_var_resolved"
  Event.CanonCompleted {} -> "canon_completed"
  Event.CanonFailed {} -> "canon_failed"
  Event.TypeConstrainStarted {} -> "type_constrain_started"
  Event.TypeConstraintSolved {} -> "type_constraint_solved"
  Event.TypeUnified {} -> "type_unified"
  Event.TypeUnifyFailed {} -> "type_unify_failed"
  Event.TypeSolveStarted {} -> "type_solve_started"
  Event.TypeSolveCompleted {} -> "type_solve_completed"
  Event.TypeSolveFailed {} -> "type_solve_failed"
  Event.TypeLetGeneralized {} -> "type_let_generalized"
  Event.OptimizeStarted {} -> "optimize_started"
  Event.OptimizeBranchInlined {} -> "optimize_branch_inlined"
  Event.OptimizeBranchJumped {} -> "optimize_branch_jumped"
  Event.OptimizeDecisionTree {} -> "optimize_decision_tree"
  Event.OptimizeCompleted {} -> "optimize_completed"
  Event.OptimizeFailed {} -> "optimize_failed"
  Event.GenerateStarted {} -> "generate_started"
  Event.GenerateCompleted {} -> "generate_completed"
  Event.CompileStarted {} -> "compile_started"
  Event.CompilePhaseEnter {} -> "compile_phase_enter"
  Event.CompilePhaseExit {} -> "compile_phase_exit"
  Event.CompileCompleted {} -> "compile_completed"
  Event.CompileFailed {} -> "compile_failed"
  Event.CacheHit {} -> "cache_hit"
  Event.CacheMiss {} -> "cache_miss"
  Event.CacheStored {} -> "cache_stored"
  Event.FFILoading {} -> "ffi_loading"
  Event.FFILoaded {} -> "ffi_loaded"
  Event.FFIMissing {} -> "ffi_missing"
  Event.WorkerSpawned {} -> "worker_spawned"
  Event.WorkerCompleted {} -> "worker_completed"
  Event.WorkerFailed {} -> "worker_failed"
  Event.KernelStarted {} -> "kernel_started"
  Event.KernelCompleted {} -> "kernel_completed"
  Event.KernelFailed {} -> "kernel_failed"
  Event.BuildStarted {} -> "build_started"
  Event.BuildModuleQueued {} -> "build_module_queued"
  Event.BuildCompleted {} -> "build_completed"
  Event.BuildFailed {} -> "build_failed"
  Event.BuildHashComputed {} -> "build_hash_computed"
  Event.BuildIncremental {} -> "build_incremental"
  Event.PackageOperation {} -> "package_operation"
  Event.ArchiveOperation {} -> "archive_operation"
  Event.InterfaceLoaded {} -> "interface_loaded"
  Event.InterfaceSaved {} -> "interface_saved"

-- | Build a minimal JSON object without pulling in aeson.
--
-- This avoids adding a heavyweight dependency for log output that may
-- never be enabled. The escaping covers the characters that appear in
-- compiler log messages (paths, module names, type signatures).
jsonObject :: [(Text, Text)] -> Text
jsonObject pairs =
  "{" <> Text.intercalate "," (fmap renderPair pairs) <> "}"
  where
    renderPair (k, v) = "\"" <> k <> "\":" <> v

-- | Wrap a text value as a JSON string with minimal escaping.
jsonString :: Text -> Text
jsonString t = "\"" <> escapeJSON t <> "\""

-- | Escape special JSON characters.
escapeJSON :: Text -> Text
escapeJSON = Text.concatMap escapeChar
  where
    escapeChar '"' = "\\\""
    escapeChar '\\' = "\\\\"
    escapeChar '\n' = "\\n"
    escapeChar '\r' = "\\r"
    escapeChar '\t' = "\\t"
    escapeChar c = Text.singleton c
