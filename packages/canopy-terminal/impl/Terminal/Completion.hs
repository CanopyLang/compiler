{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Shell completion support for Terminal framework.
--
-- This module provides comprehensive shell completion functionality
-- for command-line applications. It handles both bash and zsh
-- completion scenarios, including command names, arguments, flags,
-- and file paths with intelligent context-aware suggestions.
--
-- == Key Functions
--
-- * 'processAutoComplete' - Main completion entry point
-- * 'generateSuggestions' - Context-aware suggestion generation
-- * 'parseCompletionContext' - Parse shell completion environment
-- * 'suggestCommands' - Command name completion
--
-- == Completion Flow
--
-- 1. Detect completion request from environment variables
-- 2. Parse completion context (cursor position, current line)
-- 3. Determine completion type (command, argument, flag)
-- 4. Generate appropriate suggestions
-- 5. Output suggestions for shell consumption
--
-- == Shell Integration
--
-- The completion system integrates with shell completion frameworks
-- through standard environment variables:
--
-- * @COMP_LINE@ - Current command line
-- * @COMP_POINT@ - Cursor position in line
-- * @COMP_WORDS@ - Word array (bash-specific)
--
-- == Usage Examples
--
-- @
-- import qualified Terminal.Completion as Completion
--
-- -- Process completion in application
-- args <- getArgs
-- Completion.processAutoComplete commands args
--
-- -- Generate suggestions for context
-- suggestions <- Completion.generateSuggestions commands context
-- @
--
-- @since 0.19.1
module Terminal.Completion
  ( -- * Main Completion Interface
    processAutoComplete,
    processAutoCompleteSimple,

    -- * Suggestion Generation
    generateSuggestions,
    suggestCommands,
    suggestArguments,
    suggestFlags,

    -- * Context Processing
    parseCompletionContext,
    createCompletionContext,
    findCompletionIndex,

    -- * Utilities
    isCompletionRequest,
    outputSuggestions,
  )
where

import Control.Lens ((&), (.~), (^.))
import qualified Data.List as List
import qualified System.Environment as Environment
import qualified System.Exit as Exit
import qualified Terminal.Chomp as Chomp
import Terminal.Internal
  ( Args,
    Flags,
  )
import qualified Terminal.Parser as Parser
import Terminal.Types
  ( AppConfig (..),
    Command (..),
    CompletionContext (..),
    SuggestionIndex (..),
    acCommands,
    ccChunks,
    ccIndex,
    ccLine,
    ccPoint,
    cmdName,
  )
import qualified Terminal.Types as Types
import qualified Text.Read as Read

-- | Process auto-completion request for multi-command application.
--
-- Detects completion requests from shell environment variables,
-- parses the completion context, generates appropriate suggestions,
-- and outputs them for shell consumption.
--
-- The function checks for completion environment and exits early
-- if no completion is requested. Otherwise, it processes the
-- completion context and generates suggestions based on the
-- current command line state.
--
-- ==== Examples
--
-- >>> processAutoComplete config ["prog", "0", "1"]
-- -- Checks environment and generates completions
--
-- >>> processAutoComplete config ["prog", "make", "--"]
-- -- Suggests flags for make command
--
-- ==== Shell Integration
--
-- This function integrates with bash/zsh completion through:
--   * Environment variable detection
--   * Appropriate exit codes
--   * Formatted suggestion output
--
-- @since 0.19.1
processAutoComplete ::
  -- | Application configuration with commands
  AppConfig ->
  -- | Command-line arguments from shell
  [String] ->
  -- | Exits with completion or continues normally
  IO ()
processAutoComplete config args = do
  if not (isCompletionRequest args)
    then pure ()
    else do
      context <- parseCompletionContext
      suggestions <- generateSuggestions config context
      outputSuggestions suggestions
      Exit.exitFailure

-- | Process auto-completion for single-command application.
--
-- Simplified completion processing for applications with only
-- one command. Focuses on argument and flag completion without
-- command name suggestions.
--
-- @since 0.19.1
processAutoCompleteSimple ::
  -- | Command argument specification
  Args () ->
  -- | Command flag specification
  Flags () ->
  -- | Command-line arguments
  [String] ->
  -- | Exits with completion or continues normally
  IO ()
processAutoCompleteSimple args flags cmdArgs = do
  if not (isCompletionRequest cmdArgs)
    then pure ()
    else do
      context <- parseCompletionContext
      suggestions <- generateArgumentSuggestions args flags context
      outputSuggestions suggestions
      Exit.exitFailure

-- | Generate context-aware suggestions for completion.
--
-- Analyzes the completion context to determine what type of
-- completion is needed (command, argument, flag) and generates
-- appropriate suggestions.
--
-- The suggestion strategy:
--
-- 1. If at position 1, suggest command names
-- 2. If command found, delegate to command-specific completion
-- 3. Otherwise, suggest available commands
--
-- @since 0.19.1
generateSuggestions ::
  -- | Application configuration
  AppConfig ->
  -- | Current completion context
  CompletionContext ->
  -- | Generated suggestions
  IO [String]
generateSuggestions config context = do
  let chunks = context ^. ccChunks
      SuggestionIndex index = context ^. ccIndex

  case chunks of
    [] -> pure (getCommandNames config)
    command : args ->
      if index == 1
        then suggestCommands config command
        else case findCommand config command of
          Nothing -> pure []
          Just cmd -> suggestForCommand cmd context args

-- | Suggest command names based on prefix.
--
-- @since 0.19.1
suggestCommands ::
  -- | Application configuration
  AppConfig ->
  -- | Command prefix
  String ->
  -- | Matching command names
  IO [String]
suggestCommands config prefix = do
  let commands = getCommandNames config
      matches = filter (List.isPrefixOf prefix) commands
  pure matches

-- | Suggest arguments for specific command.
--
-- @since 0.19.1
suggestArguments ::
  -- | Command specification
  Command ->
  -- | Completion context
  CompletionContext ->
  -- | Current arguments
  [String] ->
  -- | Argument suggestions
  IO [String]
suggestArguments _command context args = do
  let SuggestionIndex index = context ^. ccIndex
      -- For now, use empty args/flags since we're using () types
      (suggestions, _) = Chomp.chomp (Just (index - 1)) args Parser.noArgs Parser.noFlags

  suggestions

-- | Suggest flags for a command matching a given prefix.
--
-- This function works with the Terminal.Types.Command record, which
-- stores flag metadata as unit type @()@. For actual shell completion
-- with real flag introspection, use the COMP_LINE-based completion
-- integrated directly into 'Terminal.app' and 'Terminal.singleCommand',
-- which access the full 'Terminal.Internal.Flags' specification.
--
-- @since 0.19.1
suggestFlags ::
  -- | Command specification
  Command ->
  -- | Flag prefix
  String ->
  -- | Flag suggestions
  IO [String]
suggestFlags _command _prefix =
  pure []

-- | Parse completion context from environment variables.
--
-- Reads shell completion environment variables to construct
-- completion context including cursor position, command line,
-- and word boundaries.
--
-- @since 0.19.1
parseCompletionContext :: IO CompletionContext
parseCompletionContext = do
  maybeLine <- Environment.lookupEnv "COMP_LINE"
  maybePoint <- Environment.lookupEnv "COMP_POINT"

  case (maybeLine, maybePoint) of
    (Just line, Just pointStr) ->
      case Read.readMaybe pointStr of
        Just point -> parseContextFromLine line point
        Nothing -> createDefaultContext line
    (Just line, Nothing) -> createDefaultContext line
    _ -> pure defaultCompletionContext

-- | Create completion context from command line and cursor position.
--
-- @since 0.19.1
createCompletionContext ::
  -- | Command line
  String ->
  -- | Cursor position
  Int ->
  -- | Completion context
  CompletionContext
createCompletionContext line point = do
  let chunks = words line
      index = findCompletionIndex point line chunks

  Types.CompletionContext (SuggestionIndex index) chunks "" 0
    & ccLine .~ line
    & ccPoint .~ point

-- | Find completion index based on cursor position.
--
-- Determines which word in the command line is being completed
-- based on cursor position and word boundaries.
--
-- @since 0.19.1
findCompletionIndex ::
  -- | Cursor position
  Int ->
  -- | Command line
  String ->
  -- | Words in command line
  [String] ->
  -- | Completion index
  Int
findCompletionIndex point _line chunks = do
  let wordPositions = scanl (+) 0 (fmap ((+ 1) . length) chunks)
      beforeCursor = takeWhile (<= point) wordPositions
  length beforeCursor

-- | Check if current invocation is completion request.
--
-- @since 0.19.1
isCompletionRequest ::
  -- | Command arguments
  [String] ->
  -- | True if completion requested
  Bool
isCompletionRequest args = length args == 3

-- | Output suggestions for shell consumption.
--
-- @since 0.19.1
outputSuggestions ::
  -- | Suggestions to output
  [String] ->
  -- | Outputs suggestions line by line
  IO ()
outputSuggestions suggestions = putStr (unlines suggestions)

-- Helper Functions

-- | Get list of command names from configuration.
getCommandNames :: AppConfig -> [String]
getCommandNames config = fmap (^. cmdName) (config ^. acCommands)

-- | Find command by name in configuration.
findCommand :: AppConfig -> String -> Maybe Command
findCommand config name =
  List.find (\cmd -> cmd ^. cmdName == name) (config ^. acCommands)

-- | Suggest completions for specific command.
suggestForCommand :: Command -> CompletionContext -> [String] -> IO [String]
suggestForCommand command context args = do
  -- Delegate to argument suggestions for now
  suggestArguments command context args

-- | Parse context from command line and cursor position.
parseContextFromLine :: String -> Int -> IO CompletionContext
parseContextFromLine line point = do
  pure $ createCompletionContext line point

-- | Create default context when parsing fails.
createDefaultContext :: String -> IO CompletionContext
createDefaultContext line =
  pure $ createCompletionContext line (length line)

-- | Default completion context for error cases.
defaultCompletionContext :: CompletionContext
defaultCompletionContext = Types.CompletionContext (SuggestionIndex 0) [] "" 0

-- | Generate argument suggestions for single command.
generateArgumentSuggestions ::
  -- | Argument specification
  Args () ->
  -- | Flag specification
  Flags () ->
  -- | Completion context
  CompletionContext ->
  -- | Generated suggestions
  IO [String]
generateArgumentSuggestions args flags context = do
  let chunks = context ^. ccChunks
      SuggestionIndex index = context ^. ccIndex
      (suggestions, _) = Chomp.chomp (Just index) chunks args flags

  suggestions
