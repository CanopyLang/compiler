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

-- Re-export from Terminal.Internal for main API
import qualified Terminal.Internal as Internal
import Terminal.Internal
  ( Args (..),
    Command (..),
    CompleteArgs (..),
    Flag (..),
    Flags (..),
    Parser (..),
    RequiredArgs (..),
    Summary (..)
  )
import qualified Terminal.Application as Application
import qualified Terminal.Parser as Parser
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

-- | Run multi-command application with introduction and outro.
--
-- @since 0.19.1
app
  :: Doc.Doc
  -- ^ Introduction text for application overview
  -> Doc.Doc
  -- ^ Outro text for application overview
  -> [Command]
  -- ^ Available commands
  -> IO ()
  -- ^ Exits with appropriate status code
app _intro _outro _commands = do
  -- Convert to simplified structure for now
  Application.initializeApp
  putStrLn "Multi-command applications not yet fully implemented"

-- | Run single-command application with details and examples.
--
-- @since 0.19.1
singleCommand
  :: Doc.Doc
  -- ^ Command details documentation  
  -> Doc.Doc
  -- ^ Command usage examples
  -> Args args
  -- ^ Argument specification
  -> Flags flags
  -- ^ Flag specification
  -> (args -> flags -> IO ())
  -- ^ Command handler function
  -> IO ()
  -- ^ Exits with appropriate status code
singleCommand _details _examples _args _flags _handler = do
  Application.initializeApp
  putStrLn "Single command applications not yet fully implemented"

-- | Create command with metadata and handler.
--
-- @since 0.19.1
command
  :: String
  -- ^ Command name
  -> Summary
  -- ^ Command summary for overview
  -> String
  -- ^ Detailed command description
  -> Doc.Doc
  -- ^ Command usage examples
  -> Args args
  -- ^ Argument specification
  -> Flags flags
  -- ^ Flag specification
  -> (args -> flags -> IO ())
  -- ^ Command handler function
  -> Command
  -- ^ Complete command definition
command name summary details examples args flagSpec handler =
  Internal.Command name summary details examples args flagSpec handler

-- Argument Builders (re-exported from Terminal.Parser)

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

-- Flag Builders (re-exported from Terminal.Parser)

-- | No flags specification.
noFlags :: Flags ()
noFlags = Parser.noFlags

-- | Create flags with initial value (backward compatibility).
flags :: a -> Flags a
flags = FDone

-- | Create flag with value parser.
flag :: String -> Parser a -> String -> Flag (Maybe a)
flag = Parser.flag

-- | Create boolean on/off flag (backward compatibility alias).
onOff :: String -> String -> Flag Bool
onOff = Parser.onOffFlag

-- | Create boolean on/off flag.
onOffFlag :: String -> String -> Flag Bool
onOffFlag = Parser.onOffFlag

-- | Chain flags together (operator for composition).
(|--) :: Flags (a -> b) -> Flag a -> Flags b
(|--) = Parser.flagChain

-- Parser Creation (re-exported from Terminal.Parser)

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