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
import System.IO (hPutStr, hPutStrLn, stdout)
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
  argStrings <- Environment.getArgs
  case argStrings of
    [] ->
      Error.exitWithOverview intro outro commands
    
    ["--help"] ->
      Error.exitWithOverview intro outro commands
      
    ["--version"] -> do
      hPutStrLn stdout (Version.toChars Version.compiler)
      Exit.exitSuccess
      
    command : chunks -> do
      case List.find (\cmd -> toName cmd == command) commands of
        Nothing ->
          Error.exitWithUnknown command (map toName commands)
          
        Just (Command _ _ details example args_ flags_ callback) ->
          if elem "--help" chunks then
            Error.exitWithHelp (Just command) details example args_ flags_
          else
            case snd (Chomp.chomp Nothing chunks args_ flags_) of
              Right (argsValue, flagsValue) ->
                callback argsValue flagsValue
              Left err ->
                Error.exitWithError err

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
singleCommand _details _examples _args _flags _handler = do
  setLocaleEncoding utf8
  putStrLn "Single command applications not yet fully implemented"
  Exit.exitFailure

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
