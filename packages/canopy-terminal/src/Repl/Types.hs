
-- | Core types for the Canopy REPL.
--
-- This module contains all the fundamental types used throughout
-- the REPL system, including input categorization, evaluation state,
-- and environment configuration.
--
-- @since 0.19.1
module Repl.Types
  ( -- * Configuration
    Flags (..),
    Env (..),

    -- * Input Types
    Input (..),
    Lines (..),
    Prefill (..),
    CategorizedInput (..),

    -- * State Types
    State (..),
    Output (..),

    -- * Control Types
    Outcome (..),
    M,

    -- * Line Operations
    addLine,
    isBlank,
    isSingleLine,
    endsWithBlankLine,
    linesToByteString,
    getFirstLine,

    -- * Output Operations
    outputToBuilder,
    toPrintName,
  )
where

import qualified Build
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import Control.Monad.State.Strict (StateT)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.UTF8 as BS_UTF8
import Data.IORef (IORef)
import Data.Map.Strict (Map)
import qualified Canopy.Data.Name as Name
import System.Exit (ExitCode)

-- | REPL command line flags and configuration options.
--
-- @since 0.19.1
data Flags = Flags
  { -- | Optional custom JavaScript interpreter path
    _maybeInterpreter :: !(Maybe FilePath),
    -- | Disable ANSI color output
    _noColors :: !Bool
  }
  deriving (Eq, Show)

-- | REPL runtime environment configuration.
--
-- Contains paths and settings determined at startup, plus mutable
-- caches for project details and build artifacts. Caching these
-- across REPL iterations avoids redundant package resolution and
-- dependency compilation on every input.
--
-- @since 0.19.1
data Env = Env
  { -- | Project root directory.
    _root :: !FilePath,
    -- | JavaScript interpreter executable path.
    _interpreter :: !FilePath,
    -- | Whether ANSI colors are enabled.
    _ansi :: !Bool,
    -- | Cached project details (packages, source dirs).
    -- Loaded once on first compilation and reused for
    -- subsequent REPL inputs.
    _cachedDetails :: !(IORef (Maybe Details.Details)),
    -- | Cached build artifacts (dependency interfaces, objects).
    -- Invalidated when imports change, otherwise reused to
    -- skip redundant dependency compilation.
    _cachedArtifacts :: !(IORef (Maybe Build.Artifacts))
  }

-- | User input categorized by type.
--
-- The REPL parses user input into these categories to determine
-- how to handle each command or code fragment.
--
-- @since 0.19.1
data Input
  = -- | Import statement
    Import !ModuleName.Raw !BS.ByteString
  | -- | Type definition (union or alias)
    Type !Name.Name !BS.ByteString
  | -- | Port declaration (not supported)
    Port
  | -- | Function or value declaration
    Decl !Name.Name !BS.ByteString
  | -- | Expression to evaluate
    Expr !BS.ByteString
  | -- | Reset REPL state
    Reset
  | -- | Exit REPL
    Exit
  | -- | Skip/ignore input
    Skip
  | -- | Show help message
    Help !(Maybe String)
  | -- | Show the type of an expression without evaluating it
    TypeOf !String
  | -- | Browse exports of a module
    Browse !(Maybe String)
  deriving (Eq, Show)

-- | Multi-line input accumulator.
--
-- Tracks the current line being entered and all previous lines
-- in reverse order for efficient prepending.
--
-- @since 0.19.1
data Lines = Lines
  { -- | Most recently entered line
    _prevLine :: !String,
    -- | Previous lines in reverse order
    _revLines :: ![String]
  }
  deriving (Eq, Show)

-- | Auto-completion prefill for multi-line input.
--
-- @since 0.19.1
data Prefill
  = -- | Add standard indentation
    Indent
  | -- | Start of a definition with the given name
    DefStart !Name.Name
  deriving (Eq, Show)

-- | Result of input categorization.
--
-- @since 0.19.1
data CategorizedInput
  = -- | Input is complete and ready for evaluation
    Done !Input
  | -- | Input needs more lines with suggested prefill
    Continue !Prefill
  deriving (Eq, Show)

-- | REPL evaluation state.
--
-- Maintains the accumulated imports, types, and declarations
-- from the current REPL session.
--
-- @since 0.19.1
data State = State
  { -- | Module imports
    _imports :: !(Map Name.Name Builder),
    -- | Type definitions
    _types :: !(Map Name.Name Builder),
    -- | Value and function declarations
    _decls :: !(Map Name.Name Builder)
  }

-- | Output type for evaluation results.
--
-- @since 0.19.1
data Output
  = -- | No output expected
    OutputNothing
  | -- | Declaration was processed
    OutputDecl !Name.Name
  | -- | Expression result to display
    OutputExpr !ByteString
  deriving (Eq, Show)

-- | Evaluation outcome determining next action.
--
-- @since 0.19.1
data Outcome
  = -- | Continue REPL with updated state
    Loop !State
  | -- | Exit REPL with the given code
    End !ExitCode

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
  Name.toBuilder Name.replValueToPrint <> BB.stringUtf8 " ="
    <> case output of
      OutputNothing -> BB.stringUtf8 " ()\n"
      OutputDecl _ -> BB.stringUtf8 " ()\n"
      OutputExpr expr ->
        foldr (\line rest -> BB.stringUtf8 "\n  " <> BB.byteString line <> rest) (BB.stringUtf8 "\n") (BSC.lines expr)

-- | Extract the name to print from output.
--
-- @since 0.19.1
toPrintName :: Output -> Maybe Name.Name
toPrintName output =
  case output of
    OutputNothing -> Nothing
    OutputDecl name -> Just name
    OutputExpr _ -> Just Name.replValueToPrint
