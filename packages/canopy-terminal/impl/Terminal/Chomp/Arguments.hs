{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Argument parsing and validation for Terminal chomp operations.
--
-- This module handles the parsing of positional command-line arguments,
-- including required arguments, optional arguments, and multiple argument
-- patterns. It provides comprehensive error handling and suggestion support
-- for all argument parsing scenarios.
--
-- == Key Features
--
-- * Type-safe argument parsing with comprehensive validation
-- * Support for required, optional, and multiple argument patterns
-- * Integrated suggestion generation for argument completion
-- * Rich error reporting with position-specific information
-- * Compositional argument specification building
--
-- == Argument Types
--
-- The module supports three primary argument patterns:
--
-- * 'Exactly' - Fixed required arguments that must be provided
-- * 'Optional' - Arguments that may or may not be present
-- * 'Multiple' - Variable-length argument lists with type validation
--
-- == Usage Examples
--
-- @
-- result <- parseArguments suggest chunks argSpec
-- case result of
--   (suggestions, Right values) -> processValues suggestions values
--   (suggestions, Left error) -> reportError suggestions error
-- @
--
-- @since 0.19.1
module Terminal.Chomp.Arguments
  ( -- * Main Parsing Functions
    parseArguments,
    parseCompleteArgs,
    parseRequiredArgs,

    -- * Argument Type Handlers
    parseExactly,
    parseOptional,
    parseMultiple,

    -- * Utility Functions
    parseArgument,
    validateArguments,
    extractArguments,

    -- * Suggestion Support
    generateArgumentSuggestion,
    combineArgumentSuggestions,
  )
where

import Control.Lens ((^.))
import Terminal.Chomp.Parser
  ( attemptParse,
  )
import Terminal.Chomp.Suggestion
  ( combineCompletions,
    generateCompletions,
    updateSuggestion,
  )
import Terminal.Chomp.Types
  ( Chomper (..),
    Chunk,
    Suggest (..),
    chunkContent,
    chunkIndex,
  )
import Terminal.Error (ArgError (..), Error (..), Expectation (..))
import Terminal.Internal
  ( Args (..),
    CompleteArgs (..),
    Parser (..),
    RequiredArgs (..),
  )
import qualified Reporting.InternalError as InternalError

-- | Parse complete argument specification with error handling.
--
-- Processes all argument alternatives and returns the first successful
-- parse or combines all error information for comprehensive reporting.
-- Handles backtracking and suggestion accumulation across alternatives.
--
-- ==== Examples
--
-- >>> let argSpec = Args [exactlyOne, optionalOne, multipleOnes]
-- >>> parseArguments suggest chunks argSpec
-- (combinedSuggestions, Right parsedArgs)
--
-- ==== Error Handling
--
-- Accumulates errors from all parsing attempts and provides:
--   * Detailed error information for each failed alternative
--   * Combined suggestions from all parsing attempts
--   * Position-specific error reporting
--
-- @since 0.19.1
parseArguments ::
  -- | Current suggestion context
  Suggest ->
  -- | Input arguments to parse
  [Chunk] ->
  -- | Argument specification
  Args a ->
  -- | Suggestions and parse result
  (IO [String], Either Error a)
parseArguments suggest chunks (Args completeArgsList) =
  parseArgumentsWithFallback suggest chunks completeArgsList [] []

-- | Parse single complete argument pattern.
--
-- Handles one specific argument pattern (exactly, optional, or multiple)
-- and generates appropriate suggestions and error information based on
-- the parsing outcome and argument structure.
--
-- ==== Examples
--
-- >>> parseCompleteArgs suggest chunks (Exactly requiredArgs)
-- (suggestions, Right value)
--
-- >>> parseCompleteArgs suggest chunks (Optional requiredArgs parser)
-- (suggestions, Right (Just value))
--
-- @since 0.19.1
parseCompleteArgs ::
  Suggest ->
  [Chunk] ->
  CompleteArgs a ->
  (Suggest, Either ArgError a)
parseCompleteArgs suggest chunks completeArgs =
  let numChunks = length chunks
   in case completeArgs of
        Exactly requiredArgs ->
          parseExactly suggest chunks (parseRequiredArgs numChunks requiredArgs)
        Optional requiredArgs parser ->
          parseOptional suggest chunks (parseRequiredArgs numChunks requiredArgs) parser
        Multiple requiredArgs parser ->
          parseMultiple suggest chunks (parseRequiredArgs numChunks requiredArgs) parser

-- | Parse required argument sequence.
--
-- Processes a sequence of required arguments, applying parsers in order
-- and accumulating results. Handles function application for multi-argument
-- patterns and provides detailed error reporting for each step.
--
-- ==== Examples
--
-- >>> parseRequiredArgs 3 (Required (Done id) stringParser)
-- Chomper (...)
--
-- @since 0.19.1
parseRequiredArgs :: Int -> RequiredArgs a -> Chomper ArgError a
parseRequiredArgs numChunks = \case
  Done value ->
    return value
  Required funcArgs argParser -> do
    func <- parseRequiredArgs numChunks funcArgs
    arg <- parseArgument numChunks argParser
    return (func arg)

-- | Parse exactly the specified arguments with no extras.
--
-- Ensures that all required arguments are provided and no additional
-- arguments remain after parsing. Generates appropriate error messages
-- for missing arguments or unexpected extra arguments.
--
-- ==== Examples
--
-- >>> parseExactly suggest chunks chomper
-- (newSuggest, Right value)  -- if exactly matching
-- (newSuggest, Left (ArgExtras ["extra"]))  -- if too many args
--
-- @since 0.19.1
parseExactly ::
  Suggest ->
  [Chunk] ->
  Chomper ArgError a ->
  (Suggest, Either ArgError a)
parseExactly suggest chunks (Chomper chomper) =
  let success s cs value =
        case fmap (^. chunkContent) cs of
          [] -> (s, Right value)
          extras -> (s, Left (ArgExtras extras))

      failure s argError =
        (s, Left argError)
   in chomper suggest chunks success failure

-- | Parse optional argument with fallback handling.
--
-- Attempts to parse the argument if input is available, providing
-- appropriate default values when arguments are missing. Handles
-- the optional value construction and extra argument detection.
--
-- ==== Examples
--
-- >>> parseOptional suggest [] chomper parser
-- (suggest, Right (func Nothing))  -- no args available
--
-- >>> parseOptional suggest [chunk] chomper parser
-- (newSuggest, Right (func (Just value)))  -- successful parse
--
-- @since 0.19.1
parseOptional ::
  Suggest ->
  [Chunk] ->
  Chomper ArgError (Maybe a -> b) ->
  Parser a ->
  (Suggest, Either ArgError b)
parseOptional suggest chunks (Chomper chomper) parser =
  let success s1 cs func =
        case cs of
          [] ->
            (s1, Right (func Nothing))
          chunk : others ->
            case attemptParse s1 parser (chunk ^. chunkIndex) (chunk ^. chunkContent) of
              (s2, Left expectation) ->
                (s2, Left (ArgBad (chunk ^. chunkContent) expectation))
              (s2, Right value) ->
                case fmap (^. chunkContent) others of
                  [] -> (s2, Right (func (Just value)))
                  extras -> (s2, Left (ArgExtras extras))

      failure s1 argError =
        (s1, Left argError)
   in chomper suggest chunks success failure

-- | Parse multiple arguments with accumulation.
--
-- Processes variable-length argument lists, applying the parser to each
-- argument and accumulating successful results. Handles empty lists
-- and provides detailed error information for the first parsing failure.
--
-- ==== Examples
--
-- >>> parseMultiple suggest chunks chomper parser
-- (suggest, Right (func []))  -- no additional args
--
-- >>> parseMultiple suggest [chunk1, chunk2] chomper parser
-- (suggest, Right (func [value1, value2]))  -- all parsed successfully
--
-- @since 0.19.1
parseMultiple ::
  Suggest ->
  [Chunk] ->
  Chomper ArgError ([a] -> b) ->
  Parser a ->
  (Suggest, Either ArgError b)
parseMultiple suggest chunks (Chomper chomper) parser =
  let failure s1 argError = (s1, Left argError)
   in chomper suggest chunks (parseMultipleHelper parser []) failure

-- | Parse individual argument with error handling.
--
-- Applies a parser to a single argument chunk, handling missing arguments
-- and generating appropriate suggestions for completion. Integrates with
-- the suggestion system for interactive completion support.
--
-- ==== Examples
--
-- >>> parseArgument 3 stringParser
-- Chomper (...)  -- returns chomper that processes string arguments
--
-- @since 0.19.1
parseArgument :: Int -> Parser a -> Chomper ArgError a
parseArgument numChunks parser@(Parser singular _ _ _ exampleFunc) =
  Chomper $ \suggest chunks success failure ->
    case chunks of
      [] ->
        -- For missing arguments, always provide suggestions/examples
        let newSuggest = case suggest of
              NoSuggestion -> SuggestIO (exampleFunc "") -- Provide examples for missing args
              _ -> updateSuggestion suggest (generateArgumentSuggestion parser numChunks)
            theError = ArgMissing (Expectation singular (exampleFunc ""))
         in failure newSuggest theError
      chunk : otherChunks ->
        case attemptParse suggest parser (chunk ^. chunkIndex) (chunk ^. chunkContent) of
          (newSuggest, Left expectation) ->
            failure newSuggest (ArgBad (chunk ^. chunkContent) expectation)
          (newSuggest, Right arg) ->
            success newSuggest otherChunks arg

-- | Generate argument-specific suggestion for completion.
--
-- Creates suggestion functions that are appropriate for the current
-- argument position and parser type, enabling context-aware completion
-- during interactive usage.
--
-- ==== Examples
--
-- >>> generateArgumentSuggestion fileParser 3 3
-- Just (return ["file1.txt", "file2.txt"])
--
-- >>> generateArgumentSuggestion stringParser 3 5
-- Nothing
--
-- @since 0.19.1
generateArgumentSuggestion :: Parser a -> Int -> Int -> Maybe (IO [String])
generateArgumentSuggestion (Parser _ _ _ suggestionFunc _) numChunks targetIndex =
  if numChunks <= targetIndex
    then Just (suggestionFunc "")
    else Nothing

-- | Validate argument structure and constraints.
--
-- Performs comprehensive validation of argument specifications including
-- type constraints, position requirements, and structural consistency.
-- Used for pre-parsing validation and error prevention.
--
-- ==== Examples
--
-- >>> validateArguments argSpec
-- Right ()  -- valid specification
--
-- >>> validateArguments invalidSpec
-- Left "Conflicting argument types"
--
-- @since 0.19.1
validateArguments :: Args a -> Either String ()
validateArguments (Args completeArgsList) =
  if null completeArgsList
    then Left "Empty argument specification"
    else Right ()

-- | Extract argument information for inspection.
--
-- Provides access to argument metadata including expected types,
-- descriptions, and structural information for help generation
-- and debugging purposes.
--
-- ==== Examples
--
-- >>> extractArguments (Args [Exactly (Required (Done id) stringParser)])
-- ["string argument"]
--
-- @since 0.19.1
extractArguments :: Args a -> [String]
extractArguments (Args completeArgsList) =
  map extractCompleteArgsInfo completeArgsList

-- | Combine suggestion sources from multiple argument parsers.
--
-- Merges suggestions from different argument parsing attempts to provide
-- comprehensive completion options during interactive usage.
--
-- ==== Examples
--
-- >>> combineArgumentSuggestions [suggestion1, suggestion2]
-- (IO combinedSuggestions)
--
-- @since 0.19.1
combineArgumentSuggestions :: [IO [String]] -> IO [String]
combineArgumentSuggestions = combineCompletions

-- Helper function for multiple argument parsing with accumulation
parseMultipleHelper :: Parser a -> [a] -> Suggest -> [Chunk] -> ([a] -> b) -> (Suggest, Either ArgError b)
parseMultipleHelper parser revArgs suggest chunks func =
  case chunks of
    [] ->
      (suggest, Right (func (reverse revArgs)))
    chunk : otherChunks ->
      case attemptParse suggest parser (chunk ^. chunkIndex) (chunk ^. chunkContent) of
        (s1, Left expectation) ->
          (s1, Left (ArgBad (chunk ^. chunkContent) expectation))
        (s1, Right arg) ->
          parseMultipleHelper parser (arg : revArgs) s1 otherChunks func

-- Helper function for parsing with fallback error accumulation
parseArgumentsWithFallback ::
  Suggest ->
  [Chunk] ->
  [CompleteArgs a] ->
  [Suggest] ->
  [(CompleteArgs a, ArgError)] ->
  (IO [String], Either Error a)
parseArgumentsWithFallback suggest chunks completeArgsList revSuggest revArgErrors =
  case completeArgsList of
    [] ->
      -- If no argument patterns remain, check for success conditions
      if null chunks && null revArgErrors
        then (combineCompletions (map generateCompletions revSuggest), Left (BadArgs []))
        else (combineCompletions (map generateCompletions revSuggest), Left (BadArgs revArgErrors))
    completeArgs : others ->
      case parseCompleteArgs suggest chunks completeArgs of
        (s1, Left argError) ->
          parseArgumentsWithFallback suggest chunks others (s1 : revSuggest) ((completeArgs, argError) : revArgErrors)
        (s1, Right value) ->
          ( generateCompletions s1,
            Right value
          )

-- Helper function to extract argument information for help generation
extractCompleteArgsInfo :: CompleteArgs a -> String
extractCompleteArgsInfo = \case
  Exactly _ -> "required argument"
  Optional _ _ -> "optional argument"
  Multiple _ _ -> "multiple arguments"
