{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Core data types and structures for Terminal chomp operations.
--
-- This module defines the fundamental types used throughout the Terminal
-- chomp system for parsing command-line arguments and flags. It provides
-- type-safe parsing with comprehensive error handling and suggestion support.
--
-- == Key Types
--
-- * 'Chomper' - Core parsing monad with continuation-based design
-- * 'Chunk' - Individual command-line argument with position tracking
-- * 'Suggest' - Suggestion system for shell completion
-- * 'FoundFlag' - Flag parsing results with value extraction
-- * 'Value' - Flag value types (definite, possible, none)
--
-- == Design Philosophy
--
-- The types use GADTs and rank-2 types to provide type safety while
-- maintaining flexibility for complex parsing scenarios. All types
-- support lens operations for efficient access and updates.
--
-- == Usage Examples
--
-- @
-- chunk <- Chunk.fromString 1 "input.txt"
-- let filename = chunk ^. chunkContent
-- let position = chunk ^. chunkIndex
-- @
--
-- @
-- suggest <- Suggestion.create 3
-- updated <- suggest & suggestTarget .~ 5
-- @
--
-- @since 0.19.1
module Terminal.Chomp.Types
  ( -- * Core Parsing Types
    Chomper (..),
    ChompResult,

    -- * Input Processing Types
    Chunk (..),
    chunkIndex,
    chunkContent,

    -- * Suggestion System Types
    Suggest (..),
    SuggestTarget (..),
    suggestTarget,

    -- * Flag Parsing Types
    FoundFlag (..),
    foundBefore,
    foundValue,
    foundAfter,
    Value (..),
    ValueType (..),
    valueIndex,
    valueContent,

    -- * Utility Functions
    createChunk,
    createSuggest,
    createFoundFlag,
    extractValue,
  )
where

import Control.Lens (makeLenses, (^.))
import qualified Reporting.InternalError as InternalError
import Terminal.Error (Error)

-- | Core parsing monad with continuation-based design.
--
-- The Chomper provides a flexible parsing framework that supports
-- backtracking, suggestion generation, and comprehensive error handling.
-- It uses continuation-passing style for efficient composition.
--
-- The type parameters are:
--   * @x@ - Error type for parsing failures
--   * @a@ - Success type for parsed values
--
-- @since 0.19.1
newtype Chomper x a
  = Chomper
      ( forall result.
        Suggest ->
        [Chunk] ->
        (Suggest -> [Chunk] -> a -> result) ->
        (Suggest -> x -> result) ->
        result
      )

-- | Result type for chomp operations combining IO suggestions and parsing results.
--
-- The first element provides IO-based suggestions for shell completion,
-- while the second element contains the actual parsing result or error.
--
-- @since 0.19.1
type ChompResult args flags = (IO [String], Either Error (args, flags))

-- | Individual command-line argument with position tracking.
--
-- Each chunk represents a single command-line argument along with its
-- position in the argument list. This enables precise error reporting
-- and suggestion targeting.
--
-- @since 0.19.1
data Chunk = Chunk
  { -- | Position in argument list (1-based)
    _chunkIndex :: !Int,
    -- | Raw argument content
    _chunkContent :: !String
  }
  deriving (Eq, Show)

-- | Suggestion system for shell completion support.
--
-- Tracks completion targets and provides mechanisms for generating
-- context-aware suggestions based on parsing state and user input.
--
-- @since 0.19.1
data Suggest
  = -- | No suggestions available
    NoSuggestion
  | -- | Target-specific suggestions
    SuggestAt !SuggestTarget
  | -- | IO-based suggestion generation
    SuggestIO !(IO [String])

instance Show Suggest where
  show NoSuggestion = "NoSuggestion"
  show (SuggestAt target) = "SuggestAt " ++ show target
  show (SuggestIO _) = "SuggestIO <IO [String]>"

-- | Eq instance for Suggest (IO [String] cases can't be compared)
instance Eq Suggest where
  NoSuggestion == NoSuggestion = True
  (SuggestAt t1) == (SuggestAt t2) = t1 == t2
  _ == _ = False -- SuggestIO cases are not comparable

-- | Suggestion target specification.
--
-- Identifies the specific argument position that should receive
-- completion suggestions during interactive usage.
--
-- @since 0.19.1
newtype SuggestTarget = SuggestTarget
  { -- | Target argument position (1-based)
    _suggestTarget :: Int
  }
  deriving (Eq, Show)

-- | Flag parsing result with context information.
--
-- Contains the parsed flag value along with the remaining arguments
-- before and after the flag position. This enables proper argument
-- reconstruction after flag extraction.
--
-- @since 0.19.1
data FoundFlag = FoundFlag
  { -- | Arguments before the flag
    _foundBefore :: ![Chunk],
    -- | Parsed flag value
    _foundValue :: !Value,
    -- | Arguments after the flag
    _foundAfter :: ![Chunk]
  }
  deriving (Eq, Show)

-- | Flag value classification and content.
--
-- Represents different types of flag values encountered during parsing,
-- from definite values (--flag=value) to possible values (--flag value)
-- to flags with no values (--flag).
--
-- @since 0.19.1
data Value
  = -- | Explicitly specified value
    DefiniteValue !ValueType
  | -- | Potentially a value (could be next flag)
    PossibleValue !Chunk
  | -- | Flag with no value
    NoValue
  deriving (Eq, Show)

-- | Classification of definite flag values.
--
-- Distinguishes between different sources and formats of flag values
-- for appropriate parsing and error reporting.
--
-- @since 0.19.1
data ValueType = ValueType
  { -- | Position where value was found
    _valueIndex :: !Int,
    -- | Raw value content
    _valueContent :: !String
  }
  deriving (Eq, Show)

-- Generate lenses for all record types
makeLenses ''Chunk
makeLenses ''SuggestTarget
makeLenses ''FoundFlag
makeLenses ''ValueType

-- | Functor instance for Chomper
instance Functor (Chomper x) where
  fmap f (Chomper parser) = Chomper $ \suggest chunks success failure ->
    parser suggest chunks (\s c a -> success s c (f a)) failure

-- | Applicative instance for Chomper
instance Applicative (Chomper x) where
  pure a = Chomper $ \suggest chunks success _ -> success suggest chunks a
  (Chomper parserF) <*> (Chomper parserA) = Chomper $ \suggest chunks success failure ->
    parserF
      suggest
      chunks
      (\s1 c1 f -> parserA s1 c1 (\s2 c2 a -> success s2 c2 (f a)) failure)
      failure

-- | Monad instance for Chomper
instance Monad (Chomper x) where
  (Chomper parserA) >>= f = Chomper $ \suggest chunks success failure ->
    parserA
      suggest
      chunks
      (\s1 c1 a -> let (Chomper parserB) = f a in parserB s1 c1 success failure)
      failure

-- | Create a new chunk with position and content.
--
-- Validates input and creates a properly structured chunk for parsing.
-- The index should be 1-based to match command-line conventions.
--
-- ==== Examples
--
-- >>> createChunk 1 "input.txt"
-- Chunk {_chunkIndex = 1, _chunkContent = "input.txt"}
--
-- >>> createChunk 0 "invalid"
-- error "Chunk index must be positive"
--
-- @since 0.19.1
createChunk :: Int -> String -> Chunk
createChunk index content
  | index <= 0 = InternalError.report
      "Terminal.Chomp.Types.createChunk"
      "Chunk index must be positive"
      "createChunk requires a strictly positive index. A non-positive index indicates a bug in the argument parser that generates chunk indices."
  | otherwise = Chunk index content

-- | Create a suggestion target for the specified position.
--
-- Validates the target position and creates an appropriate suggestion
-- structure for shell completion support.
--
-- ==== Examples
--
-- >>> createSuggest 3
-- SuggestAt (SuggestTarget {_suggestTarget = 3})
--
-- >>> createSuggest 0
-- NoSuggestion
--
-- @since 0.19.1
createSuggest :: Int -> Suggest
createSuggest index
  | index <= 0 = NoSuggestion
  | otherwise = SuggestAt (SuggestTarget index)

-- | Create a found flag structure from components.
--
-- Validates and constructs a complete flag parsing result with proper
-- argument segmentation for further processing.
--
-- ==== Examples
--
-- >>> let before = [createChunk 1 "command"]
-- >>> let value = DefiniteValue (ValueType 2 "output.txt")
-- >>> let after = [createChunk 3 "remaining"]
-- >>> createFoundFlag before value after
-- FoundFlag {...}
--
-- @since 0.19.1
createFoundFlag :: [Chunk] -> Value -> [Chunk] -> FoundFlag
createFoundFlag = FoundFlag

-- | Extract value content from different value types.
--
-- Provides a uniform interface for accessing value content regardless
-- of the value classification (definite, possible, or none).
--
-- ==== Examples
--
-- >>> let val = DefiniteValue (ValueType 1 "test")
-- >>> extractValue val
-- Just "test"
--
-- >>> extractValue NoValue
-- Nothing
--
-- @since 0.19.1
extractValue :: Value -> Maybe String
extractValue = \case
  DefiniteValue vt -> Just (vt ^. valueContent)
  PossibleValue chunk -> Just (chunk ^. chunkContent)
  NoValue -> Nothing
