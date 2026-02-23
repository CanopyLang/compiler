{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Command-line argument parsers for the CLI application.
--
-- This module provides reusable parsers for common command-line arguments
-- and flags used across different commands. All parsers follow consistent
-- patterns and provide helpful error messages and suggestions.
--
-- == Key Parsers
--
-- * Interpreter path parser for REPL configuration
-- * Port number parser for server commands
-- * Standard validation and suggestion mechanisms
--
-- == Design Principles
--
-- All parsers in this module follow these principles:
--
-- * Provide clear error messages and suggestions
-- * Include helpful examples for users
-- * Validate input appropriately
-- * Use consistent naming and patterns
--
-- @since 0.19.1
module CLI.Parsers
  ( -- * Interpreter Parsers
    createInterpreterParser,

    -- * Network Parsers
    createPortParser,

    -- * Integer Parsers
    createIntParser,
  )
where

import CLI.Types (Parser)
import qualified Terminal
import Text.Read (readMaybe)

-- | Create a parser for JavaScript interpreter paths.
--
-- Parses interpreter paths like "node" or "nodejs" for REPL configuration.
-- Accepts any string as a valid interpreter path and provides helpful
-- examples for common interpreters.
--
-- ==== Examples
--
-- @
-- let parser = createInterpreterParser
-- -- Accepts: "node", "nodejs", "/usr/bin/node"
-- @
--
-- @since 0.19.1
createInterpreterParser :: Parser String
createInterpreterParser =
  Terminal.Parser
    { Terminal._singular = "interpreter",
      Terminal._plural = "interpreters",
      Terminal._parser = Just,
      Terminal._suggest = suggestInterpreters,
      Terminal._examples = provideInterpreterExamples
    }

-- | Create a parser for port numbers.
--
-- Parses integer port numbers for server configuration. Validates that
-- the input is a valid integer and provides examples of common ports.
--
-- ==== Examples
--
-- @
-- let parser = createPortParser
-- -- Accepts: "3000", "8000", "8080"
-- -- Rejects: "abc", "70000"
-- @
--
-- @since 0.19.1
createPortParser :: Parser Int
createPortParser =
  Terminal.Parser
    { Terminal._singular = "port",
      Terminal._plural = "ports",
      Terminal._parser = parsePortNumber,
      Terminal._suggest = suggestPorts,
      Terminal._examples = providePortExamples
    }

-- | Parse and validate port numbers.
--
-- Internal parser that validates port numbers are within valid range (0-65535)
-- and rejects negative numbers or out-of-range values.
parsePortNumber :: String -> Maybe Int
parsePortNumber input = do
  port <- readMaybe input
  if port >= 0 && port <= 65535
    then Just port
    else Nothing

-- | Suggest interpreter options for user input.
--
-- Internal helper that provides suggestions for interpreter names.
-- Currently returns an empty list as interpreters are user-specific.
suggestInterpreters :: String -> IO [String]
suggestInterpreters _ = pure []

-- | Provide examples of common JavaScript interpreters.
--
-- Internal helper that shows users common interpreter names they
-- might want to use for REPL configuration.
provideInterpreterExamples :: String -> IO [String]
provideInterpreterExamples _ = pure ["node", "nodejs"]

-- | Suggest port numbers for user input.
--
-- Internal helper that provides port number suggestions. Currently
-- returns an empty list as port numbers are context-dependent.
suggestPorts :: String -> IO [String]
suggestPorts _ = pure []

-- | Provide examples of common port numbers.
--
-- Internal helper that shows users examples of commonly used
-- port numbers for development servers.
providePortExamples :: String -> IO [String]
providePortExamples _ = pure ["3000", "8000"]

-- | Create a parser for positive integer values.
--
-- Parses positive integers for use with numeric flags such as benchmark
-- iteration counts. Rejects negative numbers and non-numeric input.
--
-- ==== Examples
--
-- @
-- let parser = createIntParser
-- -- Accepts: "1", "5", "100"
-- -- Rejects: "-1", "abc", "0"
-- @
--
-- @since 0.19.1
createIntParser :: Parser Int
createIntParser =
  Terminal.Parser
    { Terminal._singular = "number",
      Terminal._plural = "numbers",
      Terminal._parser = parsePositiveInt,
      Terminal._suggest = \_ -> pure [],
      Terminal._examples = \_ -> pure ["1", "3", "10"]
    }

-- | Parse and validate positive integer values.
parsePositiveInt :: String -> Maybe Int
parsePositiveInt input = do
  n <- readMaybe input
  if n > 0 then Just n else Nothing
