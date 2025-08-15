{-# LANGUAGE GADTs #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Core error types and data structures for Terminal error handling.
--
-- This module defines the fundamental error types used throughout
-- the Terminal framework for command-line argument parsing errors,
-- flag validation errors, and user expectation management.
--
-- == Key Types
--
-- * 'Error' - Top-level error union covering all Terminal error conditions
-- * 'ArgError' - Argument-specific validation errors with detailed context
-- * 'FlagError' - Flag parsing and validation errors with suggestions
-- * 'Expectation' - Type expectations for user-friendly error messages
--
-- == Design Philosophy
--
-- All error types are designed to provide maximum context for user-friendly
-- error reporting. Each error carries sufficient information to generate
-- helpful suggestions and detailed explanations of what went wrong.
--
-- == Usage Examples
--
-- @
-- -- Argument error with expectation
-- let expectation = Expectation "file" (pure ["input.txt", "data.csv"])
-- let argError = ArgMissing expectation
--
-- -- Flag error with suggestion context
-- let flagError = FlagUnknown "--unknwon" someFlags
-- let topError = BadFlag flagError
-- @
--
-- @since 0.19.1
module Terminal.Error.Types
  ( -- * Core Error Types
    Error (..),
    ArgError (..),
    FlagError (..),
    Expectation (..),

    -- * Lenses for Expectation
    expectationType,
    expectationExamples,

    -- * Error Ranking and Comparison
    argErrorRank,
    getTopArgError,
  )
where

import Control.Lens (makeLenses)
import Terminal.Internal (CompleteArgs, Flags)

-- | Top-level error type covering all Terminal parsing failures.
--
-- This GADT provides a type-safe union of all possible error conditions
-- that can occur during command-line parsing, maintaining type information
-- where needed while allowing unified error handling.
--
-- @since 0.19.1
data Error where
  -- | Argument parsing errors with context from multiple alternatives
  BadArgs :: [(CompleteArgs a, ArgError)] -> Error
  -- | Flag parsing or validation error
  BadFlag :: FlagError -> Error

-- Show instance for Error
instance Show Error where
  show (BadArgs argErrors) = "BadArgs [" ++ show (length argErrors) ++ " errors]"
  show (BadFlag flagError) = "BadFlag (" ++ show flagError ++ ")"

-- | Argument-specific error conditions with detailed context.
--
-- Each error type carries sufficient information to generate helpful
-- error messages with examples and suggestions for the user.
--
-- @since 0.19.1
data ArgError
  = -- | Required argument is missing
    ArgMissing Expectation
  | -- | Argument value doesn't match expected format
    ArgBad String Expectation
  | -- | Unexpected extra arguments provided
    ArgExtras [String]
  deriving (Eq, Show)

-- | Flag parsing and validation error conditions.
--
-- Covers all possible flag-related errors including unknown flags,
-- value format issues, and usage pattern violations.
--
-- @since 0.19.1
data FlagError where
  -- | On/off flag given an unexpected value
  FlagWithValue :: String -> String -> FlagError
  -- | Flag value doesn't match expected format
  FlagWithBadValue :: String -> String -> Expectation -> FlagError
  -- | Flag requires a value but none provided
  FlagWithNoValue :: String -> Expectation -> FlagError
  -- | Unknown flag with context for suggestions
  FlagUnknown :: String -> Flags a -> FlagError

-- Show instance for FlagError
instance Show FlagError where
  show (FlagWithValue flag value) = "FlagWithValue " ++ show flag ++ " " ++ show value
  show (FlagWithBadValue flag value _) = "FlagWithBadValue " ++ show flag ++ " " ++ show value ++ " <expectation>"
  show (FlagWithNoValue flag _) = "FlagWithNoValue " ++ show flag ++ " <expectation>"
  show (FlagUnknown flag _) = "FlagUnknown " ++ show flag ++ " <flags>"

-- | Type expectation for error reporting and validation.
--
-- Combines type description with example generation for user-friendly
-- error messages that show both what was expected and concrete examples.
--
-- @since 0.19.1
data Expectation = Expectation
  { -- | Human-readable type description (e.g., "file", "number")
    _expectationType :: !String,
    -- | Example values for this type (e.g., ["input.txt", "data.csv"])
    _expectationExamples :: !(IO [String])
  }

-- Manual instances for Expectation since IO isn't Eq/Show
instance Eq Expectation where
  (Expectation t1 _) == (Expectation t2 _) = t1 == t2

instance Show Expectation where
  show (Expectation t _) = "Expectation " ++ t ++ " <IO [String]>"

-- Generate lenses for Expectation
makeLenses ''Expectation

-- | Calculate priority ranking for argument errors.
--
-- Lower numbers indicate higher priority for error reporting.
-- Used to select the most relevant error when multiple failures occur.
--
-- ==== Examples
--
-- >>> argErrorRank (ArgBad "invalid" expectation)
-- 0
-- >>> argErrorRank (ArgMissing expectation)
-- 1
-- >>> argErrorRank (ArgExtras ["extra"])
-- 2
--
-- @since 0.19.1
argErrorRank :: ArgError -> Int
argErrorRank err =
  case err of
    ArgBad _ _ -> 0 -- Highest priority: bad format
    ArgMissing _ -> 1 -- Medium priority: missing required
    ArgExtras _ -> 2 -- Lowest priority: unexpected extras

-- | Extract the highest priority argument error from a list.
--
-- Selects the most important error for display when multiple argument
-- parsing attempts fail. Uses 'argErrorRank' for prioritization.
--
-- ==== Examples
--
-- >>> let errors = [(args1, ArgBad "bad" exp), (args2, ArgMissing exp)]
-- >>> getTopArgError errors
-- ArgBad "bad" exp
--
-- ==== Error Conditions
--
-- Throws an error if called with an empty list (should not happen
-- in normal usage as this is called from non-empty pattern matches).
--
-- @since 0.19.1
getTopArgError :: [(CompleteArgs a, ArgError)] -> ArgError
getTopArgError argErrors =
  case argErrors of
    [] -> error "getTopArgError: empty error list"
    _ ->
      let sortedErrors = map snd argErrors
          rankedErrors = map (\e -> (argErrorRank e, e)) sortedErrors
          sortedByRank = sortByRank rankedErrors
       in case sortedByRank of
            (_, topErr) : _ -> topErr
            [] -> error "impossible: empty list after non-empty input"
  where
    sortByRank pairs = insertionSort pairs
    insertionSort [] = []
    insertionSort (x : xs) = insert x (insertionSort xs)
    insert x [] = [x]
    insert x (y : ys) = if fst x <= fst y then x : y : ys else y : insert x ys
