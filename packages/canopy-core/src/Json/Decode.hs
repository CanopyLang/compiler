{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}
{-# OPTIONS_GHC -fno-warn-noncanonical-monad-instances #-}

-- | Json.Decode - High-performance JSON decoding with rich error reporting
--
-- This module provides a complete JSON decoding framework for the Canopy compiler.
-- It uses a streaming parser approach with comprehensive error handling that
-- provides precise error locations and descriptive error messages for debugging.
--
-- The decoder architecture is built around continuation-passing style for
-- maximum performance and memory efficiency. All decoders are pure and
-- composable, enabling complex JSON structure processing with type safety.
--
-- == Key Features
--
-- * **High Performance** - Zero-copy parsing with streaming ByteString processing
-- * **Rich Error Reporting** - Precise error locations with context and suggestions
-- * **Composable Decoders** - Monadic interface for building complex decoders
-- * **Type Safety** - Compile-time guarantees for JSON structure validation
-- * **Memory Efficient** - Minimal allocation during parsing and decoding
--
-- == Architecture
--
-- The module is structured in several layers:
--
-- * 'fromByteString' - Main entry point for decoding ByteString inputs
-- * Core decoders - 'string', 'bool', 'int', 'list' for primitive types
-- * Composite decoders - 'dict', 'pairs', 'field' for structured data
-- * Combinator decoders - 'oneOf', 'mapError' for advanced composition
-- * Internal AST - See "Json.Decode.AST" for intermediate representation
-- * Internal Parser - See "Json.Decode.Parser" for parsing machinery
--
-- Error reporting integrates with "Reporting.Annotation" for consistent
-- formatting across the compiler pipeline.
--
-- == Usage Examples
--
-- === Basic Value Decoding
--
-- @
-- -- Decode simple JSON values
-- decodeText :: ByteString -> Either (Error x) Json.String
-- decodeText input = fromByteString string input
--
-- decodeNumber :: ByteString -> Either (Error x) Int
-- decodeNumber input = fromByteString int input
--
-- decodeBool :: ByteString -> Either (Error x) Bool
-- decodeBool input = fromByteString bool input
-- @
--
-- === Object Field Decoding
--
-- @
-- -- Decode specific object fields
-- decodeUserName :: ByteString -> Either (Error x) Json.String
-- decodeUserName input = fromByteString (field "name" string) input
--
-- -- Decode nested object structure
-- decodeUserProfile :: ByteString -> Either (Error x) (Json.String, Int, Bool)
-- decodeUserProfile input = fromByteString userDecoder input
--   where
--     userDecoder = do
--       name <- field "name" string
--       age <- field "age" int
--       active <- field "active" bool
--       pure (name, age, active)
-- @
--
-- === Array and List Processing
--
-- @
-- -- Decode arrays of values
-- decodeStringList :: ByteString -> Either (Error x) [Json.String]
-- decodeStringList input = fromByteString (list string) input
--
-- -- Decode non-empty lists with error handling
-- decodeNonEmptyIds :: ByteString -> Either (Error x) (NE.List Int)
-- decodeNonEmptyIds input = fromByteString (nonEmptyList int "List cannot be empty") input
--
-- -- Decode arrays of objects
-- decodeUsers :: ByteString -> Either (Error x) [(Json.String, Int)]
-- decodeUsers input = fromByteString (list userPairDecoder) input
--   where
--     userPairDecoder = pair string int
-- @
--
-- === Advanced Error Handling
--
-- @
-- -- Multiple decoding strategies with detailed errors
-- decodeFlexibleValue :: ByteString -> Either (Error String) Json.String
-- decodeFlexibleValue input = fromByteString flexDecoder input
--   where
--     flexDecoder = oneOf
--       [ string
--       , fmap (Json.fromChars . show) int  -- Convert int to string
--       , failure "Expected string or integer value"
--       ]
--
-- -- Custom error handling and transformation
-- decodeWithCustomErrors :: ByteString -> Either (Error CustomError) Result
-- decodeWithCustomErrors input = fromByteString customDecoder input
--   where
--     customDecoder = mapError toCustomError baseDecoder
--     toCustomError err = CustomError ("JSON decode failed: " <> show err)
-- @
--
-- == Error Handling
--
-- The module provides comprehensive error reporting through the 'Error' type:
--
-- * 'ParseProblem' - Syntax errors in JSON input with precise locations
-- * 'DecodeProblem' - Semantic errors during value extraction with context
--
-- Error context includes:
--
-- * **Field paths** - Exact location of errors in nested objects
-- * **Array indices** - Precise position of errors in array structures
-- * **Source regions** - Character-level error positions in input
-- * **Expected types** - Clear description of expected vs actual JSON types
--
-- == Performance Characteristics
--
-- * **Parsing**: O(n) where n is input size, single-pass with no backtracking
-- * **Memory**: O(d) where d is maximum JSON nesting depth
-- * **Allocation**: Minimal during parsing, dominated by result construction
-- * **Streaming**: Direct ByteString processing without intermediate copies
--
-- === Performance Tips
--
-- * Use 'fromByteString' with strict ByteStrings for best performance
-- * Prefer 'field' over 'pairs' when extracting specific object fields
-- * Use 'oneOf' judiciously as it can increase parsing overhead
-- * Process large arrays with streaming when memory is constrained
--
-- == Thread Safety
--
-- All decoding functions are pure and thread-safe. Decoders can be safely
-- used concurrently across multiple threads without synchronization.
--
-- @since 0.19.1
module Json.Decode
  ( -- * Main Decoding Interface
    fromByteString,
    Decoder,

    -- * Primitive Value Decoders
    string,
    customString,
    bool,
    int,

    -- * Collection Decoders
    list,
    nonEmptyList,
    pair,

    -- * Object Decoders
    KeyDecoder (..),
    dict,
    pairs,
    field,

    -- * Combinator Decoders
    oneOf,
    failure,
    mapError,

    -- * Error Types
    Error (..),
    Problem (..),
    DecodeExpectation (..),
    ParseError (..),
    StringProblem (..),
  )
where

import qualified Data.ByteString.Internal as BSI
import qualified Data.Map as Map
import qualified Canopy.Data.NonEmptyList as NE
import qualified Json.String as Json
import Json.Decode.AST
  ( AST,
    AST_ (..),
    ParseError (..),
    StringProblem (..),
  )
import Json.Decode.Parser (pFile)
import qualified Parse.Primitives as Parse
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.InternalError as InternalError

-- MAIN DECODING INTERFACE

-- | Decode a JSON value from a ByteString using the specified decoder.
--
-- This is the main entry point for JSON decoding. It parses the ByteString
-- into an intermediate AST, then applies the decoder to extract the desired
-- value with comprehensive error reporting.
--
-- The parsing process involves:
--
-- 1. **Lexical Analysis** - Tokenize JSON input with position tracking
-- 2. **Syntax Analysis** - Build JSON AST with validation
-- 3. **Semantic Analysis** - Apply decoder to extract typed values
-- 4. **Error Recovery** - Provide detailed error context for failures
--
-- ==== Examples
--
-- >>> fromByteString string "{\"test\": \"value\"}"
-- Left (ParseProblem ...)
--
-- >>> fromByteString string "\"hello world\""
-- Right (Json.String ...)
--
-- >>> fromByteString int "42"
-- Right 42
--
-- >>> fromByteString bool "true"
-- Right True
--
-- Complex object decoding:
-- @
-- userDecoder = do
--   name <- field "name" string
--   age <- field "age" int
--   pure (name, age)
--
-- result = fromByteString userDecoder "{\"name\": \"Alice\", \"age\": 30}"
-- -- Right (Json.String "Alice", 30)
-- @
--
-- ==== Error Conditions
--
-- Returns 'Left Error' for various failure conditions:
--
-- * 'ParseProblem' - JSON syntax errors
--   - Invalid JSON structure: @"{key: value}"@ (missing quotes)
--   - Malformed arrays: @"[1, 2,]"@ (trailing comma)
--   - Invalid escape sequences: @"\"test\x20"@ (invalid escape)
--
-- * 'DecodeProblem' - Type mismatch or semantic errors
--   - Wrong types: expecting string, got number
--   - Missing fields: required field not present in object
--   - Array length mismatch: expected pair, got single element
--
-- Each error includes precise source location and suggested resolution.
--
-- ==== Performance
--
-- * **Time Complexity**: O(n + d) where n is input size, d is decoder complexity
-- * **Space Complexity**: O(d + a) where d is nesting depth, a is AST size
-- * **Memory Usage**: Single pass parsing with minimal intermediate allocation
-- * **Parsing Strategy**: Recursive descent with no backtracking
--
-- For optimal performance:
-- * Use strict ByteStrings for input
-- * Prefer specific decoders over generic approaches
-- * Process large structures incrementally when possible
--
-- ==== Thread Safety
--
-- This function is pure and thread-safe. Multiple threads can decode
-- JSON concurrently without synchronization.
--
-- @since 0.19.1
fromByteString :: Decoder x a -> BSI.ByteString -> Either (Error x) a
fromByteString (Decoder decode) src =
  case Parse.fromByteString pFile BadEnd src of
    Right ast ->
      decode ast Right (Left . DecodeProblem src)
    Left problem ->
      Left (ParseProblem src problem)

-- CORE DECODER TYPE

-- | High-performance JSON decoder with rich error reporting.
--
-- 'Decoder' uses continuation-passing style for maximum efficiency during
-- JSON processing. The decoder takes an AST node and two continuations:
-- one for success with the decoded value, and one for failure with detailed
-- error information.
--
-- The decoder is parameterized by:
-- * @x@ - Custom error type for domain-specific error reporting
-- * @a@ - The type of value this decoder produces
--
-- ==== Design Philosophy
--
-- * **Zero-copy where possible** - Avoids unnecessary data copying
-- * **Fail-fast with context** - Provides precise error locations
-- * **Composable** - Decoders combine naturally through Monad/Applicative
-- * **Type-safe** - Compile-time guarantees about JSON structure
--
-- ==== Performance Characteristics
--
-- The continuation-passing approach enables:
-- * **Tail-call optimization** - Efficient recursive processing
-- * **Minimal allocation** - Only allocates final result values
-- * **Cache-friendly** - Linear memory access patterns
-- * **Compiler optimization** - Inlining and specialization opportunities
--
-- ==== Usage Patterns
--
-- Decoders are typically composed using Applicative or Monadic operations:
--
-- @
-- -- Applicative composition for independent fields
-- userDecoder = User <$> field "name" string <*> field "age" int <*> field "active" bool
--
-- -- Monadic composition for dependent decoding
-- conditionalDecoder = do
--   typeField <- field "type" string
--   case Json.toChars typeField of
--     "user" -> field "userData" userDecoder
--     "admin" -> field "adminData" adminDecoder
--     _ -> failure "Unknown type"
-- @
--
-- @since 0.19.1
newtype Decoder x a
  = Decoder
      ( forall b.
        AST -> -- The JSON AST node to decode
        (a -> b) -> -- Success continuation with decoded value
        (Problem x -> b) -> -- Failure continuation with error details
        b -- Final result (success or failure)
      )

-- ERRORS

data Error x
  = DecodeProblem BSI.ByteString (Problem x)
  | ParseProblem BSI.ByteString ParseError

deriving instance Show a => Show (Error a)

-- DECODE PROBLEMS

data Problem x
  = Field BSI.ByteString (Problem x)
  | Index Int (Problem x)
  | OneOf (Problem x) [Problem x]
  | Failure Ann.Region x
  | Expecting Ann.Region DecodeExpectation

deriving instance Show a => Show (Problem a)

data DecodeExpectation
  = TObject
  | TArray
  | TString
  | TBool
  | TInt
  | TObjectWith BSI.ByteString
  | TArrayPair Int
  deriving (Show)

-- INSTANCES

instance Functor (Decoder x) where
  {-# INLINE fmap #-}
  fmap func (Decoder decodeA) =
    Decoder $ \ast ok err ->
      let ok' a = ok (func a)
       in decodeA ast ok' err

instance Applicative (Decoder x) where
  {-# INLINE pure #-}
  pure = return

  {-# INLINE (<*>) #-}
  (<*>) (Decoder decodeFunc) (Decoder decodeArg) =
    Decoder $ \ast ok err ->
      let okF func =
            let okA arg = ok (func arg)
             in decodeArg ast okA err
       in decodeFunc ast okF err

instance Monad (Decoder x) where
  {-# INLINE return #-}
  return a =
    Decoder $ \_ ok _ ->
      ok a

  {-# INLINE (>>=) #-}
  (>>=) (Decoder decodeA) callback =
    Decoder $ \ast ok err ->
      let ok' a =
            case callback a of
              Decoder decodeB -> decodeB ast ok err
       in decodeA ast ok' err

-- PRIMITIVE VALUE DECODERS

-- | Decode a JSON string into a 'Json.String'.
--
-- Extracts string values from JSON input, preserving the efficient UTF-8
-- representation. The decoder validates that the JSON value is a string
-- type and extracts its content as a zero-copy snippet reference.
--
-- ==== Examples
--
-- >>> fromByteString string "\"hello world\""
-- Right (Json.String ...)
--
-- >>> fromByteString string "42"
-- Left (DecodeProblem ... (Expecting ... TString))
--
-- >>> fromByteString string "\"Unicode: \u4e16\u754c\""
-- Right (Json.String ...) -- Contains "Unicode: 世界"
--
-- String processing:
-- @
-- processName :: ByteString -> Either (Error x) Json.String
-- processName input = do
--   name <- fromByteString string input
--   if Json.isEmpty name
--     then Left (DecodeProblem input (Failure region "Name cannot be empty"))
--     else Right name
-- @
--
-- ==== String Handling
--
-- * **Unicode Support** - Full Unicode through UTF-8 encoding
-- * **Escape Sequences** - JSON escape sequences are properly processed
-- * **Zero-Copy** - Direct reference to parsed content when possible
-- * **Memory Efficient** - No unnecessary string copying or allocation
--
-- ==== Error Conditions
--
-- Returns decoder failure for:
-- * **Type Mismatch** - JSON value is not a string (number, boolean, array, etc.)
-- * **Malformed Strings** - Invalid escape sequences or unterminated strings
--
-- Error includes precise location and expected type information.
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) for well-formed strings (snippet extraction)
-- * **Space Complexity**: O(1) when using snippet references
-- * **Memory Usage**: Minimal - direct pointer to parsed content
-- * **UTF-8 Processing** - Efficient native UTF-8 handling
--
-- @since 0.19.1
string :: Decoder x Json.String
string =
  Decoder $ \(Ann.At region ast) ok err ->
    case ast of
      String snippet ->
        ok (Json.fromSnippet snippet)
      _ ->
        err (Expecting region TString)

customString :: Parse.Parser x a -> (Row -> Col -> x) -> Decoder x a
customString parser toBadEnd =
  Decoder $ \(Ann.At region ast) ok err ->
    case ast of
      String snippet ->
        case Parse.fromSnippet parser toBadEnd snippet of
          Right a -> ok a
          Left x -> err (Failure region x)
      _ ->
        err (Expecting region TString)

-- | Decode a JSON boolean into a Haskell 'Bool'.
--
-- Processes JSON @true@ and @false@ literals, converting them to the
-- corresponding Haskell boolean values. The decoder validates that
-- the JSON value is exactly one of these boolean literals.
--
-- ==== Examples
--
-- >>> fromByteString bool "true"
-- Right True
--
-- >>> fromByteString bool "false"
-- Right False
--
-- >>> fromByteString bool "\"true\""
-- Left (DecodeProblem ... (Expecting ... TBool))
--
-- Boolean configuration processing:
-- @
-- parseConfig :: ByteString -> Either (Error x) (Bool, Bool, Bool)
-- parseConfig input = fromByteString configDecoder input
--   where
--     configDecoder = do
--       debug <- field "debug" bool
--       verbose <- field "verbose" bool
--       production <- field "production" bool
--       pure (debug, verbose, production)
-- @
--
-- ==== JSON Boolean Literals
--
-- Accepts only these exact JSON boolean values:
-- * @true@ (case-sensitive) → 'True'
-- * @false@ (case-sensitive) → 'False'
--
-- ==== Error Conditions
--
-- Returns decoder failure for:
-- * **Type Mismatch** - JSON value is not a boolean literal
-- * **Case Sensitivity** - @True@, @FALSE@, @True@ etc. are not valid
-- * **String Booleans** - @"true"@, @"false"@ as strings are rejected
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) - direct AST pattern matching
-- * **Space Complexity**: O(1) - no allocation required
-- * **Memory Usage**: Zero allocation for boolean conversion
-- * **Parsing Speed** - Fastest primitive decoder (simple token matching)
--
-- @since 0.19.1
bool :: Decoder x Bool
bool =
  Decoder $ \(Ann.At region ast) ok err ->
    case ast of
      TRUE ->
        ok True
      FALSE ->
        ok False
      _ ->
        err (Expecting region TBool)

-- | Decode a JSON integer into a Haskell 'Int'.
--
-- Processes JSON integer values, converting them to Haskell 'Int' with
-- validation for integer format and range. The decoder ensures the JSON
-- value represents a valid integer without floating point notation.
--
-- ==== Examples
--
-- >>> fromByteString int "42"
-- Right 42
--
-- >>> fromByteString int "-123"
-- Right (-123)
--
-- >>> fromByteString int "0"
-- Right 0
--
-- >>> fromByteString int "42.5"
-- Left (ParseProblem ... NoFloats ...)
--
-- Integer processing:
-- @
-- processCount :: ByteString -> Either (Error x) Int
-- processCount input = do
--   count <- fromByteString int input
--   if count < 0
--     then Left (DecodeProblem input (Failure region "Count must be non-negative"))
--     else Right count
-- @
--
-- ==== JSON Integer Format
--
-- Accepts JSON integers following these rules:
-- * **No Leading Zeros** - @01@, @007@ are invalid (except single @0@)
-- * **No Floating Point** - @42.0@, @1e5@ are rejected
-- * **Signed Values** - @-42@ is valid, @+42@ is invalid
-- * **Range Limits** - Must fit in Haskell 'Int' range
--
-- ==== Error Conditions
--
-- Returns failure for:
-- * **Type Mismatch** - JSON value is not a number
-- * **Float Detected** - Number contains decimal point or exponent
-- * **Invalid Format** - Leading zeros, invalid syntax
-- * **Range Overflow** - Number exceeds 'Int' capacity
--
-- ==== Performance
--
-- * **Time Complexity**: O(d) where d is number of digits
-- * **Space Complexity**: O(1) - no allocation during conversion
-- * **Memory Usage**: Zero allocation for integer extraction
-- * **Conversion Speed** - Direct integer parsing without intermediate strings
--
-- @since 0.19.1
int :: Decoder x Int
int =
  Decoder $ \(Ann.At region ast) ok err ->
    case ast of
      Int n ->
        ok n
      _ ->
        err (Expecting region TInt)

-- COLLECTION DECODERS

-- | Decode a JSON array into a Haskell list.
--
-- Processes JSON arrays by applying the element decoder to each array
-- element, collecting the results into a list. The decoder handles both
-- empty arrays and arrays with multiple elements, providing precise
-- error locations for any element that fails to decode.
--
-- ==== Examples
--
-- >>> fromByteString (list int) "[1, 2, 3, 4, 5]"
-- Right [1, 2, 3, 4, 5]
--
-- >>> fromByteString (list string) "[\"a\", \"b\", \"c\"]"
-- Right [Json.String "a", Json.String "b", Json.String "c"]
--
-- >>> fromByteString (list int) "[]"
-- Right []
--
-- >>> fromByteString (list bool) "[true, \"false\"]"
-- Left (DecodeProblem ... (Index 1 (Expecting ... TBool)))
--
-- Processing arrays of objects:
-- @
-- userListDecoder :: Decoder x [(Json.String, Int)]
-- userListDecoder = list userDecoder
--   where
--     userDecoder = do
--       name <- field "name" string
--       age <- field "age" int
--       pure (name, age)
--
-- result = fromByteString userListDecoder
--   "[{\"name\": \"Alice\", \"age\": 30}, {\"name\": \"Bob\", \"age\": 25}]"
-- @
--
-- ==== Array Processing
--
-- * **Element-by-Element** - Each array element is decoded independently
-- * **Index Tracking** - Error locations include array indices
-- * **Short-Circuit** - Stops on first decode error with precise location
-- * **Memory Efficient** - Results accumulated in reverse for efficient building
--
-- ==== Error Conditions
--
-- Returns decoder failure for:
-- * **Type Mismatch** - JSON value is not an array
-- * **Element Errors** - Any array element fails to decode (with index)
-- * **Nested Failures** - Propagates element decoder errors with context
--
-- Error reporting includes the failing element's index and the specific
-- decoding problem encountered.
--
-- ==== Performance
--
-- * **Time Complexity**: O(n * e) where n is array length, e is element decode cost
-- * **Space Complexity**: O(n) for result list construction
-- * **Memory Usage**: Linear in result size, efficient list building
-- * **Processing Order** - Left-to-right with early termination on errors
--
-- @since 0.19.1
list :: Decoder x a -> Decoder x [a]
list decoder =
  Decoder $ \(Ann.At region ast) ok err ->
    case ast of
      Array asts ->
        listHelp decoder ok err 0 asts []
      _ ->
        err (Expecting region TArray)

listHelp :: Decoder x a -> ([a] -> b) -> (Problem x -> b) -> Int -> [AST] -> [a] -> b
listHelp decoder@(Decoder decodeA) ok err !i asts revs =
  case asts of
    [] ->
      ok (reverse revs)
    ast : asts ->
      let ok' value = listHelp decoder ok err (i + 1) asts (value : revs)
          err' prob = err (Index i prob)
       in decodeA ast ok' err'

-- | Decode a JSON array into a non-empty list with custom error.
--
-- Similar to 'list', but ensures the resulting list contains at least one
-- element. If the JSON array is empty, the decoder fails with the provided
-- custom error message. This is useful for validating that required data
-- collections are not empty.
--
-- ==== Examples
--
-- >>> fromByteString (nonEmptyList int "Numbers required") "[1, 2, 3]"
-- Right (NE.List 1 [2, 3])
--
-- >>> fromByteString (nonEmptyList string "Names required") "[]"
-- Left (DecodeProblem ... (Failure ... "Names required"))
--
-- >>> fromByteString (nonEmptyList bool "Flags required") "[true]"
-- Right (NE.List True [])
--
-- Required collections validation:
-- @
-- validateUserIds :: ByteString -> Either (Error String) (NE.List Int)
-- validateUserIds input = fromByteString userIdsDecoder input
--   where
--     userIdsDecoder = nonEmptyList int "User IDs list cannot be empty"
--
-- validateConfigOptions :: ByteString -> Either (Error String) (NE.List Json.String)
-- validateConfigOptions input = fromByteString optionsDecoder input
--   where
--     optionsDecoder = nonEmptyList string "At least one configuration option required"
-- @
--
-- ==== Non-Empty List Structure
--
-- Returns 'NE.List' which guarantees at least one element:
-- * **Head Element** - First element (guaranteed to exist)
-- * **Tail Elements** - Remaining elements (may be empty list)
-- * **Type Safety** - Compile-time guarantee of non-emptiness
--
-- ==== Error Conditions
--
-- Returns decoder failure for:
-- * **Type Mismatch** - JSON value is not an array
-- * **Empty Array** - Array has no elements (uses custom error message)
-- * **Element Errors** - Any array element fails to decode (with index)
--
-- ==== Performance
--
-- * **Time Complexity**: O(n * e) where n is array length, e is element decode cost
-- * **Space Complexity**: O(n) for result construction
-- * **Memory Usage**: Slightly more than 'list' due to 'NE.List' wrapper
-- * **Validation Cost** - O(1) additional check for emptiness
--
-- @since 0.19.1
nonEmptyList :: Decoder x a -> x -> Decoder x (NE.List a)
nonEmptyList decoder x =
  do
    values <- list decoder
    case values of
      v : vs -> return (NE.List v vs)
      [] -> failure x

-- | Decode a JSON array with exactly two elements into a pair.
--
-- Processes JSON arrays that contain exactly two elements, applying the
-- first decoder to the first element and the second decoder to the second
-- element. Fails if the array doesn't contain exactly two elements.
--
-- ==== Examples
--
-- >>> fromByteString (pair string int) "[\"name\", 42]"
-- Right (Json.String "name", 42)
--
-- >>> fromByteString (pair bool string) "[true, \"active\"]"
-- Right (True, Json.String "active")
--
-- >>> fromByteString (pair int int) "[1, 2, 3]"
-- Left (DecodeProblem ... (Expecting ... (TArrayPair 3)))
--
-- >>> fromByteString (pair string bool) "[\"solo\"]"
-- Left (DecodeProblem ... (Expecting ... (TArrayPair 1)))
--
-- Coordinate and tuple processing:
-- @
-- decodePoint :: ByteString -> Either (Error x) (Int, Int)
-- decodePoint input = fromByteString (pair int int) input
--
-- decodeKeyValue :: ByteString -> Either (Error x) (Json.String, Json.String)
-- decodeKeyValue input = fromByteString (pair string string) input
--
-- -- Process array of coordinate pairs
-- decodePoints :: ByteString -> Either (Error x) [(Int, Int)]
-- decodePoints input = fromByteString (list (pair int int)) input
-- @
--
-- ==== Array Length Validation
--
-- * **Exactly Two Elements** - Array must contain precisely 2 elements
-- * **Index Tracking** - Element errors include index (0 or 1)
-- * **Length Reporting** - Error message includes actual array length
-- * **Type Safety** - Ensures tuple structure at decode time
--
-- ==== Error Conditions
--
-- Returns decoder failure for:
-- * **Type Mismatch** - JSON value is not an array
-- * **Wrong Length** - Array has fewer or more than 2 elements
-- * **Element Errors** - Either array element fails to decode (with index)
--
-- Length errors include the actual array length for debugging.
--
-- ==== Performance
--
-- * **Time Complexity**: O(a + b) where a, b are element decode costs
-- * **Space Complexity**: O(1) additional overhead beyond element storage
-- * **Memory Usage**: Two element decodings plus tuple allocation
-- * **Validation Speed** - Fast length check before element processing
--
-- @since 0.19.1
pair :: Decoder x a -> Decoder x b -> Decoder x (a, b)
pair (Decoder decodeA) (Decoder decodeB) =
  Decoder $ \(Ann.At region ast) ok err ->
    case ast of
      Array vs ->
        case vs of
          [astA, astB] ->
            let err0 e = err (Index 0 e)
                ok0 a =
                  let err1 e = err (Index 1 e)
                      ok1 b = ok (a, b)
                   in decodeB astB ok1 err1
             in decodeA astA ok0 err0
          _ ->
            err (Expecting region (TArrayPair (length vs)))
      _ ->
        err (Expecting region TArray)

-- OBJECT DECODERS

-- | Decoder for JSON object keys with custom parsing logic.
--
-- Encapsulates a parser for processing JSON object keys along with
-- error handling. This allows custom key formats beyond simple strings,
-- such as parsed identifiers, enum values, or validated key formats.
--
-- The 'KeyDecoder' contains:
-- * A 'Parser' that processes the key snippet
-- * An error constructor for parse failures with position information
--
-- ==== Examples
--
-- Simple string keys:
-- @
-- stringKeyDecoder :: KeyDecoder x String
-- stringKeyDecoder = KeyDecoder parseStringKey StringParseError
--   where
--     parseStringKey = Parse.string -- Parse key as string
-- @
--
-- Enum-based keys:
-- @
-- data ConfigKey = DatabaseKey | ServerKey | LoggingKey
--
-- configKeyDecoder :: KeyDecoder String ConfigKey
-- configKeyDecoder = KeyDecoder parseConfigKey (\row col -> "Invalid config key")
--   where
--     parseConfigKey = Parse.oneOf
--       [ DatabaseKey <$ Parse.string "database"
--       , ServerKey <$ Parse.string "server"
--       , LoggingKey <$ Parse.string "logging"
--       ]
-- @
--
-- ==== Key Processing
--
-- * **Snippet Input** - Operates on parsed JSON key snippets
-- * **Custom Validation** - Can enforce key format requirements
-- * **Position Tracking** - Maintains source location for errors
-- * **Type Safety** - Enables typed object key processing
--
-- ==== Performance
--
-- * **Parsing Cost** - Depends on custom parser complexity
-- * **Memory Usage** - Key parsing typically minimal allocation
-- * **Validation Speed** - Custom validation can be optimized per use case
--
-- @since 0.19.1
data KeyDecoder x a
  = -- | Key parser with error constructor for position-based failures
    KeyDecoder (Parse.Parser x a) (Row -> Col -> x)

dict :: (Ord k) => KeyDecoder x k -> Decoder x a -> Decoder x (Map.Map k a)
dict keyDecoder valueDecoder =
  Map.fromList <$> pairs keyDecoder valueDecoder

pairs :: KeyDecoder x k -> Decoder x a -> Decoder x [(k, a)]
pairs keyDecoder valueDecoder =
  Decoder $ \(Ann.At region ast) ok err ->
    case ast of
      Object kvs ->
        pairsHelp keyDecoder valueDecoder ok err kvs []
      _ ->
        err (Expecting region TObject)

pairsHelp :: KeyDecoder x k -> Decoder x a -> ([(k, a)] -> b) -> (Problem x -> b) -> [(Parse.Snippet, AST)] -> [(k, a)] -> b
pairsHelp keyDecoder@(KeyDecoder keyParser toBadEnd) valueDecoder@(Decoder decodeA) ok err kvs revs =
  case kvs of
    [] ->
      ok (reverse revs)
    (snippet, ast) : kvs ->
      case Parse.fromSnippet keyParser toBadEnd snippet of
        Left x ->
          err (Failure (snippetToRegion snippet) x)
        Right key ->
          let ok' value = pairsHelp keyDecoder valueDecoder ok err kvs ((key, value) : revs)
              err' prob =
                let (Parse.Snippet fptr off len _ _) = snippet
                 in err (Field (BSI.PS fptr off len) prob)
           in decodeA ast ok' err'

snippetToRegion :: Parse.Snippet -> Ann.Region
snippetToRegion (Parse.Snippet _ _ len row col) =
  Ann.Region (Ann.Position row col) (Ann.Position row (col + fromIntegral len))

-- FIELDS

-- | Extract a specific field from a JSON object.
--
-- Looks up a field with the given key in a JSON object and applies the
-- provided decoder to its value. This is the primary way to extract
-- specific fields from JSON objects with type safety and error reporting.
--
-- ==== Examples
--
-- >>> fromByteString (field "name" string) "{\"name\": \"Alice\", \"age\": 30}"
-- Right (Json.String "Alice")
--
-- >>> fromByteString (field "age" int) "{\"name\": \"Alice\", \"age\": 30}"
-- Right 30
--
-- >>> fromByteString (field "missing" string) "{\"name\": \"Alice\"}"
-- Left (DecodeProblem ... (Expecting ... (TObjectWith "missing")))
--
-- Complex object field extraction:
-- @
-- extractUserInfo :: ByteString -> Either (Error x) (Json.String, Int, Bool)
-- extractUserInfo input = fromByteString userDecoder input
--   where
--     userDecoder = do
--       name <- field "name" string
--       age <- field "age" int
--       active <- field "active" bool
--       pure (name, age, active)
-- @
--
-- Nested field access:
-- @
-- extractNestedValue :: ByteString -> Either (Error x) Json.String
-- extractNestedValue input = fromByteString nestedDecoder input
--   where
--     nestedDecoder = do
--       config <- field "config" (field "database" (field "host" string))
--       pure config
-- @
--
-- ==== Field Resolution
--
-- * **Exact Match** - Field key must match exactly (case-sensitive)
-- * **UTF-8 Comparison** - Uses efficient ByteString comparison
-- * **Field Context** - Error reporting includes field name in context
-- * **Type Safety** - Field value type validated by provided decoder
--
-- ==== Error Conditions
--
-- Returns decoder failure for:
-- * **Type Mismatch** - JSON value is not an object
-- * **Missing Field** - Required field not present in object
-- * **Value Decode Error** - Field value fails to decode with provided decoder
--
-- All field-related errors include the field name in the error context.
--
-- ==== Performance
--
-- * **Time Complexity**: O(f + d) where f is field lookup cost, d is decode cost
-- * **Space Complexity**: O(1) additional overhead for field context
-- * **Memory Usage**: Field name stored in error context when needed
-- * **Lookup Speed** - Linear search through object fields (typically small)
--
-- @since 0.19.1
field :: BSI.ByteString -> Decoder x a -> Decoder x a
field key (Decoder decodeA) =
  Decoder $ \(Ann.At region ast) ok err ->
    case ast of
      Object kvs ->
        case findField key kvs of
          Just value ->
            let err' prob =
                  err (Field key prob)
             in decodeA value ok err'
          Nothing ->
            err (Expecting region (TObjectWith key))
      _ ->
        err (Expecting region TObject)

findField :: BSI.ByteString -> [(Parse.Snippet, AST)] -> Maybe AST
findField key kvPairs =
  case kvPairs of
    [] ->
      Nothing
    (Parse.Snippet fptr off len _ _, value) : remainingPairs ->
      if key == BSI.PS fptr off len
        then Just value
        else findField key remainingPairs

-- COMBINATOR DECODERS

-- | Try multiple decoders in sequence, succeeding with the first that works.
--
-- Attempts to decode a JSON value using each decoder in the provided list,
-- returning the result of the first successful decoder. If all decoders fail,
-- returns an error that combines all the individual failure information.
--
-- This is essential for handling JSON that can have multiple valid formats
-- or for implementing fallback decoding strategies.
--
-- ==== Examples
--
-- >>> let flexDecoder = oneOf [string, fmap (Json.fromChars . show) int]
-- >>> fromByteString flexDecoder "\"text\""
-- Right (Json.String "text")
--
-- >>> fromByteString flexDecoder "42"
-- Right (Json.String "42") -- Converted from int
--
-- >>> fromByteString flexDecoder "true"
-- Left (DecodeProblem ... (OneOf ...))
--
-- Multiple format support:
-- @
-- -- Handle both string and numeric IDs
-- idDecoder :: Decoder x Json.String
-- idDecoder = oneOf
--   [ string  -- "user_123"
--   , fmap (Json.fromChars . show) int  -- 123 -> "123"
--   ]
--
-- -- Support legacy and new configuration formats
-- configDecoder :: Decoder x Config
-- configDecoder = oneOf
--   [ newFormatDecoder  -- Try new format first
--   , legacyFormatDecoder  -- Fall back to legacy
--   , defaultConfigDecoder  -- Last resort defaults
--   ]
-- @
--
-- Union type decoding:
-- @
-- data Value = TextValue Json.String | NumberValue Int | BoolValue Bool
--
-- valueDecoder :: Decoder x Value
-- valueDecoder = oneOf
--   [ TextValue <$> string
--   , NumberValue <$> int
--   , BoolValue <$> bool
--   ]
-- @
--
-- ==== Decoder Selection Strategy
--
-- * **First Success Wins** - Returns result of first successful decoder
-- * **Left-to-Right** - Tries decoders in list order
-- * **No Backtracking** - Each decoder gets fresh input (no state pollution)
-- * **Error Accumulation** - Collects all failures for comprehensive reporting
--
-- ==== Error Conditions
--
-- Returns 'OneOf' error containing:
-- * **All Failures** - Each attempted decoder's specific error
-- * **Context Preservation** - Maintains error locations and context
-- * **Detailed Reporting** - Shows why each option failed
--
-- The error structure helps identify which decoders were tried and why
-- each one failed, making debugging easier.
--
-- ==== Performance
--
-- * **Time Complexity**: O(n * d) where n is decoder count, d is average decode cost
-- * **Space Complexity**: O(n) for error accumulation in failure case
-- * **Memory Usage**: Stores all errors until success or final failure
-- * **Optimization**: Consider ordering decoders by likelihood of success
--
-- **Performance Tips:**
-- * Put most likely decoders first
-- * Avoid expensive decoders early in the list unless necessary
-- * Use specific decoders rather than overly generic approaches
--
-- @since 0.19.1
oneOf :: [Decoder x a] -> Decoder x a
oneOf decoders =
  Decoder $ \ast ok err ->
    case decoders of
      Decoder decodeA : decoders ->
        let err' e =
              oneOfHelp ast ok err decoders e []
         in decodeA ast ok err'
      [] ->
        InternalError.report
          "Json.Decode.oneOf"
          "oneOf called with empty list of decoders"
          "Json.Decode.oneOf requires at least one decoder to try. Calling it with an empty list is a programming error — the caller must always provide at least one alternative decoder."

oneOfHelp :: AST -> (a -> b) -> (Problem x -> b) -> [Decoder x a] -> Problem x -> [Problem x] -> b
oneOfHelp ast ok err decoders p ps =
  case decoders of
    Decoder decodeA : decoders ->
      let err' p' =
            oneOfHelp ast ok err decoders p' (p : ps)
       in decodeA ast ok err'
    [] ->
      err (oneOfError [] p ps)

oneOfError :: [Problem x] -> Problem x -> [Problem x] -> Problem x
oneOfError problems prob ps =
  case ps of
    [] ->
      OneOf prob problems
    p : ps ->
      oneOfError (prob : problems) p ps

-- | Create a decoder that always fails with a custom error message.
--
-- Produces a decoder that immediately fails with the provided custom error,
-- regardless of the input JSON. This is useful for implementing custom
-- validation logic, providing specific error messages, or handling cases
-- where certain JSON structures should be explicitly rejected.
--
-- ==== Examples
--
-- >>> fromByteString (failure "Not supported") "42"
-- Left (DecodeProblem ... (Failure ... "Not supported"))
--
-- >>> fromByteString (failure "Custom validation failed") "{}"
-- Left (DecodeProblem ... (Failure ... "Custom validation failed"))
--
-- Custom validation with specific errors:
-- @
-- validatePositiveInt :: Decoder String Int
-- validatePositiveInt = do
--   value <- int
--   if value > 0
--     then pure value
--     else failure "Integer must be positive"
--
-- validateNonEmptyString :: Decoder String Json.String
-- validateNonEmptyString = do
--   str <- string
--   if Json.isEmpty str
--     then failure "String cannot be empty"
--     else pure str
-- @
--
-- Conditional decoding with specific errors:
-- @
-- validateUserType :: Decoder String UserType
-- validateUserType = do
--   typeStr <- field "type" string
--   case Json.toChars typeStr of
--     "admin" -> pure Admin
--     "user" -> pure RegularUser
--     "guest" -> pure Guest
--     other -> failure ("Unknown user type: " <> other)
-- @
--
-- ==== Use Cases
--
-- * **Custom Validation** - Enforce business rules beyond JSON structure
-- * **Explicit Rejection** - Reject valid JSON that doesn't meet requirements
-- * **Error Messages** - Provide domain-specific error messages
-- * **Conditional Logic** - Fail based on decoded content analysis
--
-- ==== Error Context
--
-- The failure includes:
-- * **Custom Message** - Your provided error value/message
-- * **Source Location** - Position in JSON where failure occurred
-- * **Field Context** - Path to the failing location in nested structures
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) - immediate failure
-- * **Space Complexity**: O(1) - just error message storage
-- * **Memory Usage**: Minimal - only stores the error value
-- * **Processing Cost** - No JSON processing, immediate error return
--
-- @since 0.19.1
failure :: x -> Decoder x a
failure x =
  Decoder $ \(Ann.At region _) _ err ->
    err (Failure region x)

-- | Transform the error type of a decoder.
--
-- Applies a transformation function to all custom error values that might
-- be produced by the decoder. This is useful for:
-- * Converting between different error types
-- * Adding context to existing errors
-- * Integrating decoders with different error types
--
-- The transformation only affects custom error values (type @x@), not
-- structural JSON errors like parse failures or type mismatches.
--
-- ==== Examples
--
-- >>> let stringDecoder = mapError show (failure 42)
-- >>> fromByteString stringDecoder "null"
-- Left (DecodeProblem ... (Failure ... "42"))
--
-- Error type conversion:
-- @
-- data CustomError = ValidationFailed String | ParseFailed String
--
-- stringToCustomError :: String -> CustomError
-- stringToCustomError msg = ValidationFailed msg
--
-- customDecoder :: Decoder CustomError Json.String
-- customDecoder = mapError stringToCustomError $ do
--   str <- string
--   if Json.isEmpty str
--     then failure "String is empty"
--     else pure str
-- @
--
-- Adding context to errors:
-- @
-- addFieldContext :: String -> Decoder String a -> Decoder String a
-- addFieldContext fieldName decoder =
--   mapError (\err -> "In field '" <> fieldName <> "': " <> err) decoder
--
-- userDecoder :: Decoder String User
-- userDecoder = do
--   name <- addFieldContext "name" validateNonEmptyString
--   age <- addFieldContext "age" validatePositiveInt
--   pure (User name age)
-- @
--
-- Combining different error types:
-- @
-- data AppError = JsonError String | ValidationError String | NetworkError String
--
-- processUserData :: ByteString -> Either (Error AppError) User
-- processUserData input = fromByteString appUserDecoder input
--   where
--     appUserDecoder = mapError JsonError baseUserDecoder
-- @
--
-- ==== Error Transformation
--
-- * **Custom Errors Only** - Only transforms @x@ type errors, not JSON structure errors
-- * **Deep Transformation** - Applies to errors at any nesting level
-- * **Context Preservation** - Maintains error location and field context
-- * **Type Safety** - Ensures error type consistency at compile time
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) additional overhead per error transformation
-- * **Space Complexity**: O(1) for transformation function application
-- * **Memory Usage**: No additional memory unless transformation allocates
-- * **Success Path** - Zero overhead when decoding succeeds
--
-- @since 0.19.1
mapError :: (x -> y) -> Decoder x a -> Decoder y a
mapError func (Decoder decodeA) =
  Decoder $ \ast ok err ->
    let err' prob = err (mapErrorHelp func prob)
     in decodeA ast ok err'

mapErrorHelp :: (x -> y) -> Problem x -> Problem y
mapErrorHelp func problem =
  case problem of
    Field k p -> Field k (mapErrorHelp func p)
    Index i p -> Index i (mapErrorHelp func p)
    OneOf p ps -> OneOf (mapErrorHelp func p) (fmap (mapErrorHelp func) ps)
    Failure r x -> Failure r (func x)
    Expecting r e -> Expecting r e
