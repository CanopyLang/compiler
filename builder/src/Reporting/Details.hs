{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Details - Dependency resolution progress tracking for Canopy build processes
--
-- This module provides comprehensive progress tracking for dependency resolution,
-- including download progress, cache hits, build status, and real-time progress
-- display. It implements a state machine that tracks dependencies through various
-- stages of the resolution process.
--
-- == Progress Tracking Stages
--
-- Dependencies progress through these stages:
--
-- 1. **Start** - Initialize with total dependency count
-- 2. **Cached** - Dependencies found in local cache (skip download)
-- 3. **Requested** - Dependencies requested from package registry
-- 4. **Received/Failed** - Download completion (success or failure)
-- 5. **Built/Broken** - Compilation completion (success or failure)
--
-- == State Management
--
-- The dependency state ('DState') maintains counters for each stage:
--
-- * 'total' - Total number of dependencies to process
-- * 'cached' - Dependencies found in local cache
-- * 'requested' - Dependencies requested from remote registry
-- * 'received' - Dependencies successfully downloaded
-- * 'failed' - Dependencies that failed to download
-- * 'built' - Dependencies successfully compiled
-- * 'broken' - Dependencies that failed compilation
--
-- == Real-Time Progress Display
--
-- For terminal output, the module provides live progress updates:
--
-- @
-- Verifying dependencies (3/10)
-- ● package-a 1.2.3
-- ● package-b 2.1.0
-- ✗ package-c 1.0.0
-- Dependencies ready!
-- @
--
-- == Usage Examples
--
-- === Basic Dependency Tracking
--
-- @
-- -- Track dependency resolution with terminal output
-- style <- terminal
-- dependencies <- trackDetails style $ \key -> do
--   report key (DStart 5)  -- 5 total dependencies
--   
--   -- Check cache first
--   cached <- getCachedDependencies
--   mapM_ (\_ -> report key DCached) cached
--   
--   -- Download remaining dependencies
--   remaining <- downloadDependencies uncached
--   mapM_ (\(pkg, ver) -> report key (DReceived pkg ver)) remaining
--   
--   return allDependencies
-- @
--
-- === Silent Dependency Resolution
--
-- @
-- -- No progress output for automated builds
-- let style = silent
-- deps <- trackDetails style $ \key -> do
--   -- Progress reports are ignored in silent mode
--   report key (DStart 10)
--   resolveDependencies projectConfig
-- @
--
-- == Thread Safety
--
-- The terminal implementation uses concurrent threads with channel communication.
-- The background thread safely updates progress display while the main thread
-- performs dependency work. All progress messages are serialized through channels.
--
-- @since 0.19.1
module Reporting.Details
  ( -- * Dependency Tracking
    DKey
  , DMsg(..)
  , DState
  , trackDetails
    -- * State Accessors
  , getTotal
  , getBuilt
  , getCached
  , getRequested
  , getReceived
  , getFailed
  , getBroken
    -- * Lens Accessors
  , total
  , cached
  , requested
  , received
  , failed
  , built
  , broken
  ) where

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Concurrent (Chan, forkIO, newChan, readChan, writeChan, takeMVar, putMVar)
import Control.Lens (makeLenses, (^.))
import Control.Monad (when)
import Reporting.Key (Key(..))
import Reporting.Platform (goodMark, badMark)
import qualified Reporting.Doc as Doc
import qualified Reporting.Exit.Help as Help
import Reporting.Style (Style(..))
import System.IO (hFlush, stdout)

-- | Key type for dependency tracking messages.
--
-- Specialized key for sending dependency resolution progress updates.
-- Used with 'trackDetails' to report dependency download, caching,
-- and resolution progress.
--
-- @since 0.19.1
type DKey = Key DMsg

-- | Internal state for dependency resolution progress tracking.
--
-- Maintains counters for dependencies in different stages of the resolution
-- process. All fields are strict to prevent space leaks during long-running
-- dependency resolution operations.
--
-- The state progression typically follows:
-- 1. Start with total count
-- 2. Some dependencies found in cache (cached)
-- 3. Remaining dependencies requested from registry (requested)
-- 4. Downloads complete successfully (received) or fail (failed)
-- 5. Dependencies built successfully (built) or broken (broken)
--
-- ==== Lens Access
--
-- All fields have generated lenses for convenient access and updates:
--
-- * 'total' - Total number of dependencies
-- * 'cached' - Dependencies found in local cache
-- * 'requested' - Dependencies requested from remote registry
-- * 'received' - Dependencies successfully downloaded
-- * 'failed' - Dependencies that failed to download
-- * 'built' - Dependencies successfully compiled
-- * 'broken' - Dependencies that failed compilation
--
-- @since 0.19.1
data DState = DState
  { _total :: !Int,     -- ^ Total number of dependencies to process
    _cached :: !Int,    -- ^ Dependencies found in local cache
    _requested :: !Int, -- ^ Dependencies requested from remote registry
    _received :: !Int,  -- ^ Dependencies successfully downloaded
    _failed :: !Int,    -- ^ Dependencies that failed to download
    _built :: !Int,     -- ^ Dependencies successfully compiled
    _broken :: !Int     -- ^ Dependencies that failed compilation
  }

-- | Progress messages for dependency resolution tracking.
--
-- Represents different stages and events during dependency resolution.
-- Each message type corresponds to a specific state transition in the
-- dependency resolution process.
--
-- ==== Message Flow
--
-- Typical message sequence:
--
-- 1. 'DStart' - Initialize with total dependency count
-- 2. 'DCached' - For each dependency found in cache
-- 3. 'DRequested' - When starting download requests
-- 4. 'DReceived'/'DFailed' - For each download completion
-- 5. 'DBuilt'/'DBroken' - For each compilation completion
--
-- @since 0.19.1
data DMsg
  = -- | Initialize tracking with total dependency count.
    --
    -- Sent at the beginning of dependency resolution to establish
    -- the total number of dependencies that need processing.
    DStart !Int
  | -- | Indicate a dependency was found in local cache.
    --
    -- Sent for each dependency that doesn't need downloading
    -- because it's already available locally.
    DCached
  | -- | Indicate a dependency download was requested.
    --
    -- Sent when initiating download requests to the package registry.
    -- May trigger "Starting downloads..." message on first request.
    DRequested
  | -- | Indicate successful dependency download.
    --
    -- Sent when a package download completes successfully.
    -- Includes package name and version for progress display.
    DReceived !Pkg.Name !V.Version
  | -- | Indicate failed dependency download.
    --
    -- Sent when a package download fails due to network issues,
    -- missing packages, or other download problems.
    DFailed !Pkg.Name !V.Version
  | -- | Indicate successful dependency compilation.
    --
    -- Sent when a dependency is successfully compiled and ready for use.
    DBuilt
  | -- | Indicate failed dependency compilation.
    --
    -- Sent when a dependency fails to compile due to syntax errors,
    -- type errors, or other compilation issues.
    DBroken

-- Generate lenses for DState
makeLenses ''DState

-- | Track dependency resolution progress with style-specific output.
--
-- Manages dependency resolution progress reporting by creating an appropriate
-- progress tracking context based on the output style. For terminal output,
-- spawns a background thread to handle live progress updates while the main
-- thread performs dependency work.
--
-- The function provides a 'DKey' to the callback for sending progress messages.
-- Progress is tracked through a state machine that counts dependencies in
-- various states (cached, requested, received, failed, built, broken).
--
-- ==== Examples
--
-- @
-- -- Track dependency resolution with terminal output
-- style <- terminal
-- dependencies <- trackDetails style $ \key -> do
--   report key (DStart 5)  -- 5 total dependencies
--   
--   -- Check cache first
--   cached <- getCachedDependencies
--   mapM_ (\_ -> report key DCached) cached
--   
--   -- Download remaining dependencies
--   remaining <- downloadDependencies uncached
--   mapM_ (\(pkg, ver) -> report key (DReceived pkg ver)) remaining
--   
--   return allDependencies
-- @
--
-- @
-- -- Silent dependency resolution (no progress output)
-- let style = silent
-- deps <- trackDetails style $ \key -> do
--   -- Progress reports are ignored in silent mode
--   report key (DStart 10)
--   resolveDependencies projectConfig
-- @
--
-- ==== Progress Display
--
-- Terminal style shows real-time progress:
--
-- @
-- Verifying dependencies (3/10)
-- ● package-a 1.2.3
-- ● package-b 2.1.0  
-- ✗ package-c 1.0.0
-- Dependencies ready!
-- @
--
-- ==== Thread Safety
--
-- The terminal implementation uses concurrent threads with MVar synchronization.
-- The background thread safely updates progress display while the main thread
-- performs dependency work. All progress messages are serialized through channels.
--
-- ==== Error Handling
--
-- Exceptions from the callback propagate normally. The background progress thread
-- is properly cleaned up via channel termination, even if the callback fails.
--
-- @since 0.19.1
trackDetails :: Style -> (DKey -> IO a) -> IO a
trackDetails style callback =
  case style of
    Silent ->
      callback (Key (\_ -> return ()))
    Json ->
      callback (Key (\_ -> return ()))
    Terminal mvar ->
      do
        chan <- newChan

        _ <- forkIO $
          do
            _ <- takeMVar mvar
            detailsLoop chan (DState 0 0 0 0 0 0 0)
            putMVar mvar ()

        answer <- callback (Key (writeChan chan . Just))
        writeChan chan Nothing
        return answer

-- | Main loop for dependency progress display.
--
-- Processes dependency messages from the channel and updates the progress
-- display accordingly. Continues until a termination signal (Nothing) is
-- received, then displays the final status message.
--
-- @since 0.19.1
detailsLoop :: Chan (Maybe DMsg) -> DState -> IO ()
detailsLoop chan state@(DState totalCount _ _ _ _ builtCount _) =
  do
    msg <- readChan chan
    case msg of
      Just dmsg ->
        detailsStep dmsg state >>= detailsLoop chan
      Nothing ->
        putStrLn . clear (toBuildProgress totalCount totalCount) $
          ( if builtCount == totalCount
              then "Dependencies ready!"
              else "Dependency problem!"
          )

-- | Process a single dependency message and update state.
--
-- Handles each type of dependency message, updating counters and
-- displaying appropriate progress information. Returns the updated state.
--
-- @since 0.19.1
detailsStep :: DMsg -> DState -> IO DState
detailsStep msg (DState totalVal cachedVal rqst rcvd failedVal builtVal brokenVal) =
  case msg of
    DStart numDependencies ->
      return (DState numDependencies 0 0 0 0 0 0)
    DCached ->
      putTransition (DState totalVal (cachedVal + 1) rqst rcvd failedVal builtVal brokenVal)
    DRequested ->
      do
        when (rqst == 0) (putStrLn "Starting downloads...\n")
        return (DState totalVal cachedVal (rqst + 1) rcvd failedVal builtVal brokenVal)
    DReceived pkg vsn ->
      do
        putDownload goodMark pkg vsn
        putTransition (DState totalVal cachedVal rqst (rcvd + 1) failedVal builtVal brokenVal)
    DFailed pkg vsn ->
      do
        putDownload badMark pkg vsn
        putTransition (DState totalVal cachedVal rqst rcvd (failedVal + 1) builtVal brokenVal)
    DBuilt ->
      putBuilt (DState totalVal cachedVal rqst rcvd failedVal (builtVal + 1) brokenVal)
    DBroken ->
      putBuilt (DState totalVal cachedVal rqst rcvd failedVal builtVal (brokenVal + 1))

-- | Display download result for a specific package.
--
-- Shows the success/failure mark, package name, and version in a formatted way.
--
-- @since 0.19.1
putDownload :: Doc.Doc -> Pkg.Name -> V.Version -> IO ()
putDownload mark pkg vsn =
  Help.toStdout . Doc.indent 2 $
    ( mark
        Doc.<+> Doc.fromPackage pkg
        Doc.<+> Doc.fromVersion vsn
        Doc.<> "\n"
    )

-- | Update progress display during download phase.
--
-- Checks if all downloads are complete and updates the progress counter
-- accordingly. Handles the transition from download to build phase.
--
-- @since 0.19.1
putTransition :: DState -> IO DState
putTransition state@(DState totalVal cachedVal _ rcvd failedVal builtVal brokenVal) =
  if cachedVal + rcvd + failedVal < totalVal
    then return state
    else do
      let char = if rcvd + failedVal == 0 then '\r' else '\n'
      putStrFlush (char : toBuildProgress (builtVal + brokenVal + failedVal) totalVal)
      return state

-- | Update progress display during build phase.
--
-- Shows build progress when all downloads are complete and dependencies
-- are being compiled.
--
-- @since 0.19.1
putBuilt :: DState -> IO DState
putBuilt state@(DState totalVal cachedVal _ rcvd failedVal builtVal brokenVal) =
  do
    when (totalVal == cachedVal + rcvd + failedVal) . putStrFlush $ 
      ('\r' : toBuildProgress (builtVal + brokenVal + failedVal) totalVal)
    return state

-- | Format build progress message.
--
-- Creates a progress string showing current build count and total.
--
-- @since 0.19.1
toBuildProgress :: Int -> Int -> String
toBuildProgress builtCount totalCount =
  "Verifying dependencies (" <> (show builtCount <> ("/" <> (show totalCount <> ")")))

-- | Clear previous output and replace with new message.
--
-- Overwrites the previous line with spaces to clear it, then displays
-- the new message. Used for updating progress displays in place.
--
-- @since 0.19.1
clear :: String -> String -> String
clear before after =
  '\r' : (replicate (length before) ' ' <> ('\r' : after))

-- | Output string and immediately flush stdout.
--
-- Ensures that output appears immediately in the terminal, which is
-- important for progress indicators and real-time feedback.
--
-- @since 0.19.1
putStrFlush :: String -> IO ()
putStrFlush str =
  putStr str >> hFlush stdout

-- STATE ACCESSORS

-- | Get total dependency count from dependency state.
getTotal :: DState -> Int
getTotal state = state ^. total

-- | Get count of successfully built dependencies from state.
getBuilt :: DState -> Int
getBuilt state = state ^. built

-- | Get count of cached dependencies from state.
getCached :: DState -> Int
getCached state = state ^. cached

-- | Get count of requested dependencies from state.
getRequested :: DState -> Int
getRequested state = state ^. requested

-- | Get count of successfully received dependencies from state.
getReceived :: DState -> Int
getReceived state = state ^. received

-- | Get count of failed dependency downloads from state.
getFailed :: DState -> Int
getFailed state = state ^. failed

-- | Get count of broken dependencies from state.
getBroken :: DState -> Int
getBroken state = state ^. broken