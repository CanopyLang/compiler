{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Reporting - Comprehensive reporting system for Canopy build processes
--
-- This module provides a complete reporting framework for the Canopy compiler,
-- handling user interaction, progress tracking, error reporting, and output
-- formatting across different environments. The system supports multiple output
-- styles (silent, JSON, terminal) and provides real-time progress tracking for
-- dependency resolution and compilation phases.
--
-- The reporting system is designed around a key abstraction that allows
-- decoupling of progress reporting from business logic, enabling consistent
-- progress tracking across all build operations while maintaining flexibility
-- in output formatting.
--
-- == Architecture Overview
--
-- The reporting system is decomposed into focused sub-modules:
--
-- * **"Reporting.Style"** - Output style configuration (Silent, Json, Terminal)
-- * **"Reporting.Attempt"** - Exception handling and error reporting
-- * **"Reporting.Platform"** - Platform compatibility utilities  
-- * **"Reporting.Key"** - Progress reporting abstraction
-- * **"Reporting.Ask"** - User interaction and prompts
-- * **"Reporting.Details"** - Dependency resolution progress tracking
-- * **"Reporting.Build"** - Build progress and code generation reporting
--
-- Each sub-module has a single, focused responsibility while this coordinating
-- module provides a unified API through re-exports.
--
-- == Key Features
--
-- * **Multi-Style Output** - Silent, JSON, and interactive terminal modes
-- * **Real-Time Progress** - Live dependency and compilation progress tracking
-- * **Exception Handling** - Comprehensive error reporting with context preservation
-- * **User Interaction** - Prompts and confirmations with proper input validation
-- * **Cross-Platform** - Windows and Unix terminal compatibility
-- * **Thread-Safe** - Concurrent progress tracking with proper synchronization
--
-- == Usage Examples
--
-- === Basic Progress Tracking
--
-- @
-- -- Track dependency resolution with progress updates
-- style <- terminal
-- result <- trackDetails style $ \key -> do
--   report key (DStart 5)
--   -- ... dependency resolution work ...
--   report key DCached
--   report key (DReceived packageName version)
--   pure dependencies
-- @
--
-- === Error Handling with Style
--
-- @
-- -- Handle compilation errors with appropriate output style
-- style <- terminal
-- result <- attemptWithStyle style compileErrorToReport $ do
--   compileModule "src/Main.elm"
-- -- Automatically formats and displays errors based on style
-- @
--
-- === User Interaction
--
-- @
-- -- Prompt user for confirmation
-- shouldContinue <- ask "Continue with build? [Y/n]: "
-- when shouldContinue $ do
--   putStrLn "Proceeding with build..."
-- @
--
-- == Error Handling
--
-- All reporting functions handle exceptions gracefully:
--
-- * 'UserInterrupt' - Preserves Ctrl+C behavior for clean termination
-- * 'SomeException' - Captures unexpected errors with diagnostic information
-- * Build errors - Formats compilation and dependency errors consistently
-- * Thread exceptions - Properly synchronizes concurrent progress updates
--
-- Error messages include context, suggestions, and links to community resources
-- for resolution assistance.
--
-- == Performance Characteristics
--
-- * **Time Complexity**: O(1) for progress updates, O(n) for final rendering
-- * **Space Complexity**: O(1) state tracking, O(k) where k is message count
-- * **Memory Usage**: Minimal allocation for progress tracking
-- * **Concurrency**: Thread-safe progress updates with MVar synchronization
--
-- == Thread Safety
--
-- All reporting functions are thread-safe. The terminal style uses MVar
-- synchronization to prevent output corruption during concurrent updates.
-- Multiple threads can safely report progress simultaneously.
--
-- @since 0.19.1
module Reporting
  ( -- * Output Styles
    Style
  , silent
  , json
  , terminal
    -- * Exception Handling
  , attempt
  , attemptWithStyle
    -- * Progress Reporting
  , Key
  , report
  , ignorer
  , ask
    -- * Dependency Tracking
  , DKey
  , DMsg(..)
  , DState
  , trackDetails
    -- * Build Tracking
  , BKey
  , BMsg(..)
  , BResult
  , trackBuild
    -- * Code Generation Reporting
  , reportGenerate
    -- * State Accessors
  , getTotal
  , getBuilt
  , getCached
  , getRequested
  , getReceived
  , getFailed
  , getBroken
  ) where

-- Re-exports from focused sub-modules
import Reporting.Style
  ( Style
  , silent
  , json
  , terminal
  )
import Reporting.Attempt
  ( attempt
  , attemptWithStyle
  )
import Reporting.Key
  ( Key
  , report
  , ignorer
  )
import Reporting.Ask
  ( ask
  )
import Reporting.Details
  ( DKey
  , DMsg(..)
  , DState
  , trackDetails
  , getTotal
  , getBuilt
  , getCached
  , getRequested
  , getReceived
  , getFailed
  , getBroken
  )
import Reporting.Build
  ( BKey
  , BMsg(..)
  , BResult
  , trackBuild
  , reportGenerate
  )

