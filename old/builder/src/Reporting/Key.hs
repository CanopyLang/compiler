{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Key - Progress reporting abstraction for Canopy build processes
--
-- This module provides a message passing abstraction that decouples progress
-- reporting from specific output implementations. The key system allows
-- business logic to report progress without knowing whether output goes to
-- terminal, JSON, or is suppressed entirely.
--
-- == Design Philosophy
--
-- The Key abstraction follows these principles:
--
-- * **Decoupling** - Business logic is independent of output formatting
-- * **Flexibility** - Same code works with different output styles
-- * **Testability** - Progress reporting can be easily mocked or ignored
-- * **Thread Safety** - Concurrent progress updates are properly synchronized
--
-- == Key Types
--
-- Keys are parameterized by message type, enabling type-safe progress reporting:
--
-- * @Key DMsg@ - For dependency resolution progress
-- * @Key BMsg@ - For build compilation progress  
-- * @Key CustomMsg@ - For custom progress tracking
--
-- == Message Flow
--
-- The typical pattern for using keys:
--
-- 1. Create a key with appropriate message handling
-- 2. Pass key to business logic functions
-- 3. Business logic sends progress messages via the key
-- 4. Key handler formats and displays messages according to style
--
-- == Usage Examples
--
-- === Basic Progress Reporting
--
-- @
-- -- Business logic reports progress without knowing output format
-- processWork :: Key ProgressMsg -> IO Result
-- processWork key = do
--   report key (Started 10)
--   items <- getWorkItems
--   forM_ items $ \item -> do
--     processItem item
--     report key ItemComplete
--   report key (Finished 10)
--   return result
-- @
--
-- === Creating Keys for Different Styles
--
-- @
-- -- Terminal key with live progress display
-- terminalKey <- createTerminalKey progressDisplay
-- result <- processWork terminalKey
-- 
-- -- Silent key that ignores all messages
-- let silentKey = ignorer
-- result <- processWork silentKey
-- 
-- -- Test key that collects messages for verification
-- (testKey, messages) <- createTestKey
-- result <- processWork testKey
-- assertEqual expectedMessages (reverse messages)
-- @
--
-- === Thread-Safe Progress Updates
--
-- @
-- -- Multiple threads can safely report progress
-- concurrently_ 
--   (processGroup1 key)
--   (processGroup2 key)
-- -- Key ensures synchronized output without corruption
-- @
--
-- == Error Handling
--
-- Keys are designed to never fail - message sending is a best-effort operation
-- that continues even if individual message handling encounters issues. This
-- ensures that progress reporting problems don't interrupt business logic.
--
-- @since 0.19.1
module Reporting.Key
  ( -- * Key Types
    Key(..)
    -- * Message Sending
  , report
    -- * Key Constructors
  , ignorer
  ) where

-- | Message passing key for progress reporting.
--
-- Provides an abstraction for sending progress messages without coupling
-- the reporting logic to specific output implementations. The key encapsulates
-- a message handler function that can format and display progress updates
-- according to the current reporting style.
--
-- This design allows business logic to report progress without knowing whether
-- output goes to terminal, JSON, or is suppressed entirely.
--
-- ==== Type Parameters
--
-- * @msg@ - The message type for progress updates (e.g., 'DMsg', 'BMsg')
--
-- @since 0.19.1
newtype Key msg = Key (msg -> IO ())

-- | Send a progress message using the provided key.
--
-- Transmits a progress update through the key's message handler. The actual
-- handling behavior depends on the reporting style that created the key:
--
-- * Silent keys ignore all messages
-- * JSON keys may buffer messages for structured output
-- * Terminal keys update live progress displays
--
-- ==== Examples
--
-- @
-- -- Report dependency download progress
-- report key (DReceived packageName version)
-- 
-- -- Report compilation completion
-- report key BDone
-- 
-- -- Report dependency resolution start
-- report key (DStart totalCount)
-- @
--
-- ==== Thread Safety
--
-- The report function is thread-safe when used with terminal keys, as the
-- underlying MVar synchronization prevents output corruption.
--
-- @since 0.19.1
report :: Key msg -> msg -> IO ()
report (Key send) = send

-- | Create a key that ignores all messages.
--
-- Useful for testing, silent modes, or when progress reporting is not
-- needed. All messages sent to this key are discarded without any
-- processing or output.
--
-- ==== Examples
--
-- @
-- -- Use ignorer for silent operation
-- result <- processWithKey ignorer $ do
--   -- ... work that normally reports progress ...
--   report key someMessage  -- No effect
--   return result
-- @
--
-- @
-- -- Conditional progress reporting
-- key <- if verbose then terminalKey else pure ignorer
-- result <- processWithKey key workFunction
-- @
--
-- @since 0.19.1
ignorer :: Key msg
ignorer =
  Key (\_ -> return ())