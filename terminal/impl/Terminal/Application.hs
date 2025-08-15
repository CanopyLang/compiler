{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Application-level orchestration for Terminal framework.
--
-- This module provides the main application entry point and high-level
-- orchestration for command-line applications. It handles application
-- initialization, argument processing, version display, and dispatching
-- to appropriate command handlers.
--
-- == Key Functions
--
-- * 'runApp' - Main application entry point for multi-command CLIs
-- * 'runSingleCommand' - Entry point for single-command applications
-- * 'initializeApp' - Application initialization with locale setup
--
-- == Architecture
--
-- The application flow follows these steps:
--
-- 1. Initialize environment (locale, encoding)
-- 2. Parse command-line arguments
-- 3. Handle special cases (version, help, overview)
-- 4. Dispatch to appropriate command handler
-- 5. Process results and exit appropriately
--
-- == Usage Examples
--
-- @
-- import qualified Terminal.Application as App
-- import qualified Terminal.Types as Types
--
-- main :: IO ()
-- main = do
--   config <- App.createAppConfig intro outro commands
--   App.runApp config
-- @
--
-- @since 0.19.1
module Terminal.Application
  ( -- * Application Entry Points
    runApp,
    runSingleCommand,

    -- * Configuration
    createAppConfig,
    initializeApp,

    -- * Argument Processing
    processAppArguments,
    handleVersionRequest,
    handleOverviewRequest,
  )
where

import qualified Canopy.Version as Version
import Control.Lens ((&), (.~), (^.))
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import qualified System.Environment as Environment
import qualified System.Exit as Exit
import qualified Terminal.Command as Command
import qualified Terminal.Error as Error
import Terminal.Types
  ( AppConfig (..),
    Command (..),
    acCommands,
    acIntro,
    acOutro,
  )
import qualified Terminal.Types as Types
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

-- | Run multi-command application with configuration.
--
-- Initializes the application environment, processes command-line
-- arguments, and dispatches to the appropriate command handler.
-- Handles all error conditions and special requests (version, help).
--
-- The application processes arguments in this order:
--
-- 1. Initialize locale and encoding
-- 2. Parse command-line arguments
-- 3. Handle version/help requests
-- 4. Find and execute command
--
-- ==== Examples
--
-- >>> config <- createAppConfig intro outro [makeCommand, installCommand]
-- >>> runApp config
-- -- Processes command line and runs appropriate handler
--
-- ==== Error Handling
--
-- Exits with appropriate codes for:
--   * Unknown commands (suggestions provided)
--   * Parsing errors (detailed messages)
--   * Command execution failures
--
-- @since 0.19.1
runApp ::
  -- | Application configuration with commands
  AppConfig ->
  -- | Exits with appropriate code
  IO ()
runApp config = do
  initializeApp
  args <- Environment.getArgs
  processAppArguments config args

-- | Run single-command application with direct handler.
--
-- Simplified entry point for applications that implement only
-- a single command. Handles version/help but skips command
-- selection logic.
--
-- @since 0.19.1
runSingleCommand ::
  -- | Command details documentation
  Doc.Doc ->
  -- | Command examples
  Doc.Doc ->
  -- | Command handler function
  (() -> () -> IO ()) ->
  -- | Exits with appropriate code
  IO ()
runSingleCommand details examples handler = do
  initializeApp
  args <- Environment.getArgs
  Command.processSingleCommand details examples handler args

-- | Create application configuration from components.
--
-- @since 0.19.1
createAppConfig ::
  -- | Introduction text
  Doc.Doc ->
  -- | Outro text
  Doc.Doc ->
  -- | Available commands
  [Command] ->
  -- | Configured application
  IO AppConfig
createAppConfig intro outro commands = do
  pure $
    Types.defaultAppConfig
      & acIntro .~ intro
      & acOutro .~ outro
      & acCommands .~ commands

-- | Initialize application environment and encoding.
--
-- Sets up UTF-8 locale encoding to ensure proper handling
-- of international characters in command-line arguments
-- and output.
--
-- @since 0.19.1
initializeApp :: IO ()
initializeApp = setLocaleEncoding utf8

-- | Process application arguments and dispatch appropriately.
--
-- Handles the main application argument processing logic,
-- including special cases and command dispatch.
--
-- @since 0.19.1
processAppArguments ::
  -- | Application configuration
  AppConfig ->
  -- | Command-line arguments
  [String] ->
  -- | Exits with appropriate code
  IO ()
processAppArguments config args =
  case args of
    [] -> handleOverviewRequest config
    ["--help"] -> handleOverviewRequest config
    ["--version"] -> handleVersionRequest
    command : chunks -> Command.handleCommandExecution config command chunks

-- | Handle version information request and exit.
--
-- Displays the compiler version and exits successfully.
-- Used for both single and multi-command applications.
--
-- @since 0.19.1
handleVersionRequest :: IO ()
handleVersionRequest = do
  putStrLn (Version.toChars Version.compiler)
  Exit.exitSuccess

-- | Handle application overview request and exit.
--
-- Displays the application overview including introduction,
-- available commands, and usage information.
--
-- @since 0.19.1
handleOverviewRequest ::
  -- | Application configuration
  AppConfig ->
  -- | Exits with overview display
  IO ()
handleOverviewRequest config =
  Error.exitWithOverview
    (config ^. acIntro)
    (config ^. acOutro)
    [] -- Empty commands list for now since we have different Command types
