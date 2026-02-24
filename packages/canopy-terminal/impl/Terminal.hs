{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Terminal framework for building sophisticated command-line applications.
--
-- This module provides a comprehensive framework for building command-line
-- applications with robust argument parsing, flag handling, help generation,
-- and error reporting. It follows modular design principles with clear
-- separation of concerns across specialized sub-modules.
--
-- == Architecture Overview
--
-- The Terminal framework is organized into focused modules:
--
-- * 'Terminal.Internal' - Core data types and parsing logic
-- * 'Terminal.Application' - Application orchestration and entry points
-- * 'Terminal.Command' - Command execution and management
-- * 'Terminal.Parser' - Argument and flag parsing utilities
-- * 'Terminal.Completion' - Shell completion support
--
-- == Key Features
--
-- * Type-safe argument and flag parsing with GADTs
-- * Comprehensive help generation and error reporting
-- * Shell completion for bash and zsh
-- * Compositional parser combinators
-- * Rich error types with helpful suggestions
--
-- == Usage Patterns
--
-- === Multi-Command Applications
--
-- @
-- import qualified Terminal
--
-- main :: IO ()
-- main = Terminal.app intro outro
--   [ Terminal.command "build" summary details examples
--       (Terminal.optional (Terminal.fileParser [".hs"]))
--       (Terminal.flag "output" Terminal.stringParser "output directory")
--       buildHandler
--   ]
-- @
--
-- === Single-Command Applications
--
-- @
-- main :: IO ()
-- main = Terminal.singleCommand details examples
--   (Terminal.required (Terminal.fileParser []))
--   Terminal.noFlags
--   myHandler
-- @
--
-- @since 0.19.1
module Terminal
  ( -- * Application Entry Points
    app,
    singleCommand,

    -- * Command Definition
    Command (..),
    command,
    Summary (..),

    -- * Argument Builders
    Args (..),
    RequiredArgs (..),
    CompleteArgs (..),
    noArgs,
    required,
    optional,
    zeroOrMore,
    oneOrMore,
    oneOf,
    require0,
    require1,
    require2,
    require3,
    require4,
    require5,

    -- * Flag Builders
    Flags (..),
    Flag (..),
    noFlags,
    flags,
    flag,
    onOff,
    onOffFlag,
    (|--),

    -- * Parser Creation
    Parser (..),
    stringParser,
    intParser,
    floatParser,
    boolParser,
    fileParser,
  )
where

-- Core imports for Terminal functionality

import qualified Data.List as List
import qualified System.Environment as Environment
import qualified System.Exit as Exit
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import System.IO (hPutStrLn, stdout)
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

import qualified Canopy.Version as Version
import Terminal.Internal
  ( Args (..),
    Command (..),
    CompleteArgs (..),
    Flag (..),
    Flags (..),
    Parser (..),
    RequiredArgs (..),
    Summary (..),
    toName,
  )
import qualified Terminal.Chomp as Chomp
import qualified Terminal.Chomp.Flags as ChompFlags
import qualified Terminal.Error as Error
import qualified Terminal.Parser as Parser

-- | Run multi-command application with introduction and outro.
--
-- @since 0.19.1
app ::
  -- | Introduction text for application overview
  Doc.Doc ->
  -- | Outro text for application overview
  Doc.Doc ->
  -- | Available commands
  [Command] ->
  -- | Exits with appropriate status code
  IO ()
app intro outro commands = do
  setLocaleEncoding utf8

  -- Handle shell completion if COMP_LINE is set
  maybeCompLine <- Environment.lookupEnv "COMP_LINE"
  case maybeCompLine of
    Just compLine -> handleAppCompletion commands compLine
    Nothing -> runApp intro outro commands

-- | Run the application normally (no completion).
runApp ::
  Doc.Doc ->
  Doc.Doc ->
  [Command] ->
  IO ()
runApp intro outro commands = do
  argStrings <- Environment.getArgs
  case argStrings of
    [] ->
      Error.exitWithOverview intro outro commands

    ["--help"] ->
      Error.exitWithOverview intro outro commands

    ["--version"] -> do
      hPutStrLn stdout (Version.toChars Version.compiler)
      Exit.exitSuccess

    commandName : chunks ->
      case List.find (\cmd -> toName cmd == commandName) commands of
        Nothing ->
          Error.exitWithUnknown commandName (map toName commands)

        Just (Command _ _ details example args_ flags_ callback) ->
          if elem "--help" chunks then
            Error.exitWithHelp (Just commandName) details example args_ flags_
          else
            case snd (Chomp.chomp Nothing chunks args_ flags_) of
              Right (argsValue, flagsValue) ->
                callback argsValue flagsValue
              Left err ->
                Error.exitWithError err

-- | Handle shell completion for multi-command application.
--
-- Parses the COMP_LINE to determine the completion context and outputs
-- appropriate suggestions: command names, flag names, or argument hints.
handleAppCompletion :: [Command] -> String -> IO ()
handleAppCompletion commands compLine = do
  let chunks = words compLine
      trailingSpace = not (null compLine) && last compLine == ' '
      commandNames = map toName commands

  case chunks of
    -- Just the program name, suggest all commands
    [_prog] ->
      if trailingSpace
        then outputSuggestions commandNames
        else return ()

    -- Partial command name or first arg after program
    [_prog, partial] ->
      if trailingSpace
        then suggestForCommandChunks commands partial []
        else outputSuggestions (filter (List.isPrefixOf partial) commandNames)

    -- Command identified, suggest flags/args
    (_prog : cmdName : rest) ->
      suggestForCommandChunks commands cmdName rest

    _ -> return ()

  Exit.exitSuccess

-- | Suggest completions for a specific command's arguments and flags.
suggestForCommandChunks :: [Command] -> String -> [String] -> IO ()
suggestForCommandChunks commands cmdName chunks =
  case List.find (\cmd -> toName cmd == cmdName) commands of
    Nothing -> return ()
    Just (Command _ _ _ _ _ flags_ _) ->
      suggestFlagsForChunks flags_ currentWord
      where
        currentWord = if null chunks then "" else last chunks

-- | Suggest flags matching the current input prefix.
--
-- Uses 'getFlagNames' from the Chomp.Flags module to extract all
-- defined flag names from the command's flag specification, then
-- filters to those matching the current prefix.
suggestFlagsForChunks :: Flags a -> String -> IO ()
suggestFlagsForChunks flags_ prefix = do
  let flagNames = ChompFlags.getFlagNames flags_ []
      matching = filter (List.isPrefixOf prefix) flagNames
  outputSuggestions matching

-- | Output completion suggestions, one per line.
outputSuggestions :: [String] -> IO ()
outputSuggestions = mapM_ putStrLn

-- | Run single-command application with details and examples.
--
-- @since 0.19.1
singleCommand ::
  -- | Command details documentation
  Doc.Doc ->
  -- | Command usage examples
  Doc.Doc ->
  -- | Argument specification
  Args args ->
  -- | Flag specification
  Flags flags ->
  -- | Command handler function
  (args -> flags -> IO ()) ->
  -- | Exits with appropriate status code
  IO ()
singleCommand details examples args_ flags_ handler = do
  setLocaleEncoding utf8

  -- Handle shell completion if COMP_LINE is set
  maybeCompLine <- Environment.lookupEnv "COMP_LINE"
  case maybeCompLine of
    Just compLine -> handleSingleCompletion flags_ compLine
    Nothing -> runSingleCommand details examples args_ flags_ handler

-- | Run single-command application normally.
runSingleCommand ::
  Doc.Doc ->
  Doc.Doc ->
  Args args ->
  Flags flags ->
  (args -> flags -> IO ()) ->
  IO ()
runSingleCommand details examples args_ flags_ handler = do
  argStrings <- Environment.getArgs
  case argStrings of
    ["--help"] ->
      Error.exitWithHelp Nothing (renderDoc details) examples args_ flags_

    ["--version"] -> do
      hPutStrLn stdout (Version.toChars Version.compiler)
      Exit.exitSuccess

    chunks ->
      case snd (Chomp.chomp Nothing chunks args_ flags_) of
        Right (argsValue, flagsValue) ->
          handler argsValue flagsValue
        Left err ->
          Error.exitWithError err
  where
    renderDoc doc = Doc.displayS (Doc.renderPretty 0.8 80 doc) ""

-- | Handle shell completion for single-command application.
handleSingleCompletion :: Flags a -> String -> IO ()
handleSingleCompletion flags_ compLine = do
  let chunks = words compLine
      currentWord = if length chunks > 1 then last chunks else ""
  suggestFlagsForChunks flags_ currentWord
  Exit.exitSuccess

-- | Create command with metadata and handler.
--
-- @since 0.19.1
command ::
  -- | Command name
  String ->
  -- | Command summary for overview
  Summary ->
  -- | Detailed command description
  String ->
  -- | Command usage examples
  Doc.Doc ->
  -- | Argument specification
  Args args ->
  -- | Flag specification
  Flags flags ->
  -- | Command handler function
  (args -> flags -> IO ()) ->
  -- | Complete command definition
  Command
command name summary details examples args flagSpec handler =
  Command name summary details examples args flagSpec handler

-- Argument Builders - Simplified implementations

-- | No arguments specification.
noArgs :: Args ()
noArgs = Parser.noArgs

-- | Required argument specification.
required :: Parser a -> Args a
required = Parser.required

-- | Optional argument specification.
optional :: Parser a -> Args (Maybe a)
optional = Parser.optional

-- | Zero or more arguments specification.
zeroOrMore :: Parser a -> Args [a]
zeroOrMore = Parser.zeroOrMore

-- | One or more arguments specification.
oneOrMore :: Parser a -> Args (a, [a])
oneOrMore = Parser.oneOrMore

-- | Alternative argument patterns.
oneOf :: [Args a] -> Args a
oneOf = Parser.oneOf

-- | Exactly zero arguments.
require0 :: args -> Args args
require0 = Parser.require0

-- | Exactly one argument.
require1 :: (a -> args) -> Parser a -> Args args
require1 = Parser.require1

-- | Exactly two arguments.
require2 :: (a -> b -> args) -> Parser a -> Parser b -> Args args
require2 = Parser.require2

-- | Exactly three arguments.
require3 :: (a -> b -> c -> args) -> Parser a -> Parser b -> Parser c -> Args args
require3 = Parser.require3

-- | Exactly four arguments.
require4 :: (a -> b -> c -> d -> args) -> Parser a -> Parser b -> Parser c -> Parser d -> Args args
require4 = Parser.require4

-- | Exactly five arguments.
require5 :: (a -> b -> c -> d -> e -> args) -> Parser a -> Parser b -> Parser c -> Parser d -> Parser e -> Args args
require5 = Parser.require5

-- Flag Builders - Simplified implementations

-- | No flags specification.
noFlags :: Flags ()
noFlags = Parser.noFlags

-- | Create flags with initial value.
flags :: a -> Flags a
flags = FDone

-- | Create flag with value parser.
flag :: String -> Parser a -> String -> Flag (Maybe a)
flag = Parser.flag

-- | Create boolean on/off flag.
onOff :: String -> String -> Flag Bool
onOff name description = OnOff name description

-- | Create boolean on/off flag.
onOffFlag :: String -> String -> Flag Bool
onOffFlag = Parser.onOffFlag

-- | Chain flags together.
(|--) :: Flags (a -> b) -> Flag a -> Flags b
(|--) = FMore

-- Parser Creation - Simplified implementations

-- | Simple string parser.
stringParser :: String -> String -> Parser String
stringParser = Parser.stringParser

-- | Integer parser with bounds.
intParser :: Int -> Int -> Parser Int
intParser = Parser.intParser

-- | Float parser.
floatParser :: Parser Float
floatParser = Parser.floatParser

-- | Boolean parser.
boolParser :: Parser Bool
boolParser = Parser.boolParser

-- | File parser with extension filtering.
fileParser :: [String] -> Parser String
fileParser = Parser.fileParser
