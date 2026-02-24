{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unified public API for the Canopy structured logging system.
--
-- Every call site in the compiler imports this module. It reads the
-- cached 'LogConfig' once and dispatches events to the appropriate
-- sink(s). When logging is disabled, 'logEvent' short-circuits on
-- the 'IORef' read — no allocation, no formatting.
--
-- == Usage
--
-- @
-- import Logging.Event (LogEvent (..))
-- import qualified Logging.Logger as Log
--
-- compileMod :: FilePath -> IO ()
-- compileMod path = do
--   Log.logEvent (CompileStarted path)
--   (result, dur) <- Log.withTiming PhaseParse (parseFile path)
--   Log.logEvent (CompilePhaseExit PhaseParse modName dur)
-- @
--
-- @since 0.19.1
module Logging.Logger
  ( logEvent,
    logEvents,
    withTiming,
    isEnabled,
    timed,
  )
where

import Data.IORef (IORef)
import qualified Data.IORef as IORef
import qualified Data.Time.Clock as Time
import Logging.Config (LogConfig (..), OutputFormat (..))
import qualified Logging.Config as Config
import Logging.Event (Duration (..), LogEvent, Phase)
import qualified Logging.Sink as Sink
import System.IO.Unsafe (unsafePerformIO)
import qualified System.IO as IO

-- | Cached sink built from the configuration at startup.
--
-- This 'IORef' is initialized once via 'unsafePerformIO'. The sink
-- encapsulates all output logic so 'logEvent' only needs to check
-- the config guard and call the sink.
{-# NOINLINE sinkRef #-}
sinkRef :: IORef Sink.Sink
sinkRef = unsafePerformIO (buildSink >>= IORef.newIORef)

-- | Build the sink from configuration.
buildSink :: IO Sink.Sink
buildSink = do
  cfg <- Config.readConfig
  if not (_configEnabled cfg)
    then pure Sink.nullSink
    else do
      let primary = case _configFormat cfg of
            FormatCLI -> Sink.cliSink IO.stderr
            FormatJSON -> Sink.jsonSink IO.stderr
      fileSinks <- case _configFile cfg of
            Nothing -> pure []
            Just path -> do
              s <- Sink.fileSink path
              pure [s]
      pure (Sink.combineSinks (primary : fileSinks))

-- | Emit a single log event.
--
-- Short-circuits immediately when logging is disabled. When enabled,
-- checks the event's level and phase against the configuration before
-- dispatching to the sink.
logEvent :: LogEvent -> IO ()
logEvent evt = do
  cfg <- Config.readConfig
  if Config.shouldEmit cfg evt
    then do
      sink <- IORef.readIORef sinkRef
      Sink.runSink sink evt
    else pure ()

-- | Emit multiple log events.
logEvents :: [LogEvent] -> IO ()
logEvents evts = do
  cfg <- Config.readConfig
  sink <- IORef.readIORef sinkRef
  mapM_ (emitIfAllowed cfg sink) evts
  where
    emitIfAllowed cfg sink evt
      | Config.shouldEmit cfg evt = Sink.runSink sink evt
      | otherwise = pure ()

-- | Time an IO action and return the result paired with a 'Duration'.
--
-- The phase parameter is available for callers that want to emit a
-- 'CompilePhaseExit' event with the returned duration.
withTiming :: Phase -> IO a -> IO (a, Duration)
withTiming _phase action = timed action

-- | Time an IO action and return the result paired with a 'Duration'.
timed :: IO a -> IO (a, Duration)
timed action = do
  start <- Time.getCurrentTime
  result <- action
  end <- Time.getCurrentTime
  let micros = round (Time.nominalDiffTimeToSeconds (Time.diffUTCTime end start) * 1000000)
  pure (result, Duration micros)

-- | Check whether logging is enabled at all.
--
-- Useful for gating expensive event construction at TRACE level:
--
-- @
-- enabled <- Log.isEnabled
-- when enabled (Log.logEvent (TypeUnified modName t1 t2))
-- @
isEnabled :: IO Bool
isEnabled = _configEnabled <$> Config.readConfig
