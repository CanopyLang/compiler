{-# OPTIONS_GHC -Wall #-}

-- | Core types for the Canopy REPL.
--
-- This module contains all the fundamental types used throughout
-- the REPL system, including input categorization, evaluation state,
-- and environment configuration.
--
-- @since 0.19.1
module Repl.Types
  ( -- * Configuration
    Flags(..)
  , Env(..)
    -- * Input Types
  , Input(..)
  , Lines(..)  
  , Prefill(..)
  , CategorizedInput(..)
    -- * State Types
  , State(..)
  , Output(..)
    -- * Control Types
  , Outcome(..)
  , M
    -- * Line Operations
  , addLine
  , isBlank
  , isSingleLine
  , endsWithBlankLine
  , linesToByteString
  , getFirstLine
    -- * Output Operations
  , outputToBuilder
  , toPrintName
  ) where

import Control.Monad.State.Strict (StateT)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.UTF8 as BS_UTF8
import Data.Map (Map)
import qualified Data.Name as N
import qualified Canopy.ModuleName as ModuleName
import System.Exit (ExitCode)

-- | REPL command line flags and configuration options.
--
-- @since 0.19.1
data Flags = Flags
  { _maybeInterpreter :: !(Maybe FilePath)
  -- ^ Optional custom JavaScript interpreter path
  , _noColors :: !Bool
  -- ^ Disable ANSI color output
  } deriving (Eq, Show)

-- | REPL runtime environment configuration.
--
-- Contains paths and settings determined at startup.
--
-- @since 0.19.1  
data Env = Env
  { _root :: !FilePath
  -- ^ Project root directory
  , _interpreter :: !FilePath  
  -- ^ JavaScript interpreter executable path
  , _ansi :: !Bool
  -- ^ Whether ANSI colors are enabled
  } deriving (Eq, Show)

-- | User input categorized by type.
--
-- The REPL parses user input into these categories to determine
-- how to handle each command or code fragment.
--
-- @since 0.19.1
data Input
  = Import !ModuleName.Raw !BS.ByteString
  -- ^ Import statement
  | Type !N.Name !BS.ByteString
  -- ^ Type definition (union or alias)
  | Port
  -- ^ Port declaration (not supported)
  | Decl !N.Name !BS.ByteString
  -- ^ Function or value declaration
  | Expr !BS.ByteString
  -- ^ Expression to evaluate
  | Reset
  -- ^ Reset REPL state
  | Exit
  -- ^ Exit REPL
  | Skip
  -- ^ Skip/ignore input
  | Help !(Maybe String)
  -- ^ Show help message
  deriving (Eq, Show)

-- | Multi-line input accumulator.
--
-- Tracks the current line being entered and all previous lines
-- in reverse order for efficient prepending.
--
-- @since 0.19.1
data Lines = Lines
  { _prevLine :: !String
  -- ^ Most recently entered line
  , _revLines :: ![String]
  -- ^ Previous lines in reverse order
  } deriving (Eq, Show)

-- | Auto-completion prefill for multi-line input.
--
-- @since 0.19.1
data Prefill
  = Indent
  -- ^ Add standard indentation
  | DefStart !N.Name
  -- ^ Start of a definition with the given name
  deriving (Eq, Show)

-- | Result of input categorization.
--
-- @since 0.19.1
data CategorizedInput
  = Done !Input
  -- ^ Input is complete and ready for evaluation
  | Continue !Prefill
  -- ^ Input needs more lines with suggested prefill
  deriving (Eq, Show)

-- | REPL evaluation state.
--
-- Maintains the accumulated imports, types, and declarations
-- from the current REPL session.
--
-- @since 0.19.1
data State = State
  { _imports :: !(Map N.Name Builder)
  -- ^ Module imports
  , _types :: !(Map N.Name Builder)
  -- ^ Type definitions
  , _decls :: !(Map N.Name Builder)
  -- ^ Value and function declarations
  }

-- | Output type for evaluation results.
--
-- @since 0.19.1
data Output
  = OutputNothing
  -- ^ No output expected
  | OutputDecl !N.Name
  -- ^ Declaration was processed
  | OutputExpr !ByteString
  -- ^ Expression result to display
  deriving (Eq, Show)

-- | Evaluation outcome determining next action.
--
-- @since 0.19.1
data Outcome
  = Loop !State
  -- ^ Continue REPL with updated state
  | End !ExitCode
  -- ^ Exit REPL with the given code

-- | REPL monad stack.
--
-- @since 0.19.1
type M = StateT State IO

-- * Line Operations

-- | Add a new line to the accumulated lines.
--
-- @since 0.19.1
addLine :: String -> Lines -> Lines
addLine line (Lines x xs) = Lines line (x : xs)

-- | Check if all lines are blank or whitespace.
--
-- @since 0.19.1
isBlank :: Lines -> Bool
isBlank (Lines prev rev) = 
  null rev && all (== ' ') prev

-- | Check if only one line has been entered.
--
-- @since 0.19.1
isSingleLine :: Lines -> Bool
isSingleLine (Lines _ rev) = null rev

-- | Check if the most recent line is blank.
--
-- @since 0.19.1
endsWithBlankLine :: Lines -> Bool
endsWithBlankLine (Lines prev _) = all (== ' ') prev

-- | Convert accumulated lines to a ByteString.
--
-- @since 0.19.1
linesToByteString :: Lines -> BS_UTF8.ByteString
linesToByteString (Lines prev rev) =
  BS_UTF8.fromString (unlines (reverse (prev : rev)))

-- | Get the first line that was entered.
--
-- @since 0.19.1
getFirstLine :: Lines -> String
getFirstLine (Lines x xs) =
  case xs of
    [] -> x
    y : ys -> getFirstLine (Lines y ys)

-- * Output Operations

-- | Convert output to a ByteString builder.
--
-- @since 0.19.1
outputToBuilder :: Output -> Builder
outputToBuilder output =
  N.toBuilder N.replValueToPrint <> " ="
    <> case output of
      OutputNothing -> " ()\n"
      OutputDecl _ -> " ()\n"
      OutputExpr expr ->
        foldr (\line rest -> "\n  " <> B.byteString line <> rest) "\n" (BSC.lines expr)

-- | Extract the name to print from output.
--
-- @since 0.19.1
toPrintName :: Output -> Maybe N.Name
toPrintName output =
  case output of
    OutputNothing -> Nothing
    OutputDecl name -> Just name
    OutputExpr _ -> Just N.replValueToPrint