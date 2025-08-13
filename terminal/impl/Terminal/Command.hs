{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Command execution and management for Terminal framework.
--
-- This module handles individual command execution, including command
-- lookup, argument parsing, help processing, and handler dispatch.
-- It provides both single-command and multi-command application
-- support with comprehensive error handling.
--
-- == Key Functions
--
-- * 'handleCommandExecution' - Execute specific command with arguments
-- * 'processSingleCommand' - Handle single-command application logic
-- * 'findCommand' - Locate command by name with suggestions
-- * 'executeCommand' - Parse arguments and execute command handler
--
-- == Command Processing Flow
--
-- 1. Locate command by name (with suggestions for typos)
-- 2. Check for help requests (--help flag)
-- 3. Parse arguments and flags using command specification
-- 4. Execute command handler with parsed values
-- 5. Handle any execution errors appropriately
--
-- == Usage Examples
--
-- @
-- import qualified Terminal.Command as Command
-- import qualified Terminal.Types as Types
--
-- -- Handle command execution
-- Command.handleCommandExecution config "make" ["--output", "dist"]
--
-- -- Process single command
-- Command.processSingleCommand details examples handler ["input.txt"]
-- @
--
-- @since 0.19.1
module Terminal.Command
  ( -- * Command Execution
    handleCommandExecution,
    processSingleCommand,
    
    -- * Command Management
    findCommand,
    executeCommand,
    executeCommandWithHelp,
    
    -- * Command Creation
    createCommand,
    createCommandMeta,
  )
where

import Control.Lens ((^.))
import qualified Data.List as List
import qualified Terminal.Chomp as Chomp
import qualified Terminal.Error as Error
import Terminal.Types
  ( AppConfig (..),
    Command (..),
    CommandMeta (..),
    acCommands,
    cmdHandler,
    cmdMeta,
    cmdName,
    cmArgs,
    cmDetails,
    cmExample,
    cmFlags
  )
import Terminal.Internal
  ( Args,
    Flags
  )
import qualified Terminal.Parser as Parser
import qualified Terminal.Types as Types
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

-- | Handle command execution within multi-command application.
--
-- Locates the specified command, processes help requests, and
-- executes the command with parsed arguments. Provides helpful
-- suggestions for unknown commands.
--
-- The execution flow:
--
-- 1. Find command by name in application configuration
-- 2. Display suggestions if command not found
-- 3. Process help requests with command-specific documentation
-- 4. Parse arguments and flags according to command specification
-- 5. Execute command handler with parsed values
--
-- ==== Examples
--
-- >>> handleCommandExecution config "build" ["--release", "src/"]
-- -- Finds build command and executes with parsed arguments
--
-- >>> handleCommandExecution config "biuld" []
-- -- Shows "Did you mean 'build'?" and exits
--
-- ==== Error Conditions
--
-- Exits with appropriate codes for:
--   * Unknown commands (with suggestions)
--   * Argument parsing failures
--   * Command execution errors
--
-- @since 0.19.1
handleCommandExecution
  :: AppConfig
  -- ^ Application configuration with commands
  -> String
  -- ^ Command name to execute
  -> [String]
  -- ^ Command arguments
  -> IO ()
  -- ^ Exits with appropriate status
handleCommandExecution config commandName args = do
  case findCommand config commandName of
    Nothing -> Error.exitWithUnknown commandName (getCommandNames config)
    Just command -> executeCommandWithHelp command args

-- | Process single-command application with direct handler.
--
-- Simplified command processing for applications that implement
-- only one command. Handles help requests and argument parsing
-- without command lookup logic.
--
-- @since 0.19.1
processSingleCommand
  :: Doc.Doc
  -- ^ Command details documentation
  -> Doc.Doc
  -- ^ Command examples
  -> (() -> () -> IO ())
  -- ^ Command handler function
  -> [String]
  -- ^ Command arguments
  -> IO ()
  -- ^ Exits with appropriate status
processSingleCommand details examples handler args = do
  if "--help" `elem` args
    then Error.exitWithHelp Nothing (show details) examples Parser.noArgs Parser.noFlags
    else executeWithArguments handler args

-- | Find command by name in application configuration.
--
-- Searches through available commands to find exact name match.
-- Used for command lookup before execution.
--
-- @since 0.19.1
findCommand
  :: AppConfig
  -- ^ Application configuration
  -> String
  -- ^ Command name to find
  -> Maybe Command
  -- ^ Found command or Nothing
findCommand config name =
  List.find (\cmd -> cmd ^. cmdName == name) (config ^. acCommands)

-- | Execute command with help processing.
--
-- Checks for help requests before executing command. If help
-- is requested, displays command-specific help. Otherwise,
-- parses arguments and executes the command handler.
--
-- @since 0.19.1
executeCommandWithHelp
  :: Command
  -- ^ Command to execute
  -> [String]
  -- ^ Command arguments
  -> IO ()
  -- ^ Exits with appropriate status
executeCommandWithHelp command args = do
  if "--help" `elem` args
    then displayCommandHelp command
    else executeCommand command args

-- | Execute command after parsing arguments and flags.
--
-- Parses command arguments according to the command's argument
-- and flag specifications, then executes the command handler
-- with the parsed values.
--
-- @since 0.19.1
executeCommand
  :: Command
  -- ^ Command to execute
  -> [String]
  -- ^ Raw command arguments
  -> IO ()
  -- ^ Exits with appropriate status
executeCommand command args = do
  let handler = command ^. cmdHandler
      -- Use empty args/flags since we're working with () types
  
  case parseCommandArguments args Parser.noArgs Parser.noFlags of
    Right (parsedArgs, parsedFlags) -> handler parsedArgs parsedFlags
    Left err -> Error.exitWithError err

-- | Create command with metadata and handler.
--
-- @since 0.19.1
createCommand
  :: String
  -- ^ Command name
  -> CommandMeta
  -- ^ Command metadata
  -> (() -> () -> IO ())
  -- ^ Command handler
  -> Command
  -- ^ Complete command definition
createCommand name meta handler = Command
  { _cmdName = name
  , _cmdMeta = meta
  , _cmdHandler = handler
  }

-- | Create command metadata from components.
--
-- @since 0.19.1
createCommandMeta
  :: Types.Summary
  -- ^ Command summary
  -> String
  -- ^ Command details
  -> Doc.Doc
  -- ^ Command examples
  -> CommandMeta
  -- ^ Complete metadata
createCommandMeta summary details examples = Types.defaultCommandMeta
  { _cmSummary = summary
  , _cmDetails = details
  , _cmExample = examples
  }

-- Helper Functions

-- | Get list of all command names from configuration.
getCommandNames :: AppConfig -> [String]
getCommandNames config = fmap (^. cmdName) (config ^. acCommands)

-- | Display command-specific help and exit.
displayCommandHelp :: Command -> IO ()
displayCommandHelp command = do
  let name = command ^. cmdName
      meta = command ^. cmdMeta
      details = meta ^. cmDetails
      examples = meta ^. cmExample
      -- Use empty args/flags since we're working with () types
  
  Error.exitWithHelp (Just name) details examples Parser.noArgs Parser.noFlags

-- | Parse command arguments using Chomp parser.
parseCommandArguments
  :: [String]
  -- ^ Raw arguments
  -> Args ()
  -- ^ Argument specification
  -> Flags ()
  -- ^ Flag specification
  -> Either Error.Error ((), ())
  -- ^ Parsed values or error
parseCommandArguments args argSpec flagSpec =
  snd $ Chomp.chomp Nothing args argSpec flagSpec

-- | Execute command with simplified argument processing.
executeWithArguments
  :: (() -> () -> IO ())
  -- ^ Command handler
  -> [String]
  -- ^ Arguments
  -> IO ()
  -- ^ Exits appropriately
executeWithArguments handler args = do
  case parseCommandArguments args Parser.noArgs Parser.noFlags of
    Right (parsedArgs, parsedFlags) -> handler parsedArgs parsedFlags
    Left err -> Error.exitWithError err