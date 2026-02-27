{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE UnboxedTuples #-}

-- | Internal JSON parser implementation for Json.Decode.
--
-- This module provides the low-level JSON parsing machinery including
-- AST construction, string parsing with escape sequence handling,
-- integer parsing, and whitespace processing.
--
-- These functions are internal to the Json.Decode system and not
-- exposed in the public API.
--
-- @since 0.19.1
module Json.Decode.Parser
  ( pFile,
    pValue,
    pObject,
    pObjectHelp,
    pField,
    pArray,
    pArrayHelp,
    pString,
    StringStatus (..),
    pStringHelp,
    processStringChar,
    processStringEscape,
    processEscapeChar,
    processUnicodeEscape,
    isHex,
    spaces,
    eatSpaces,
    pInt,
    parseIntDigit,
    parseZeroInt,
    ZeroValidationContext (..),
    validateZeroSuffix,
    parseNonZeroInt,
    IntStatus (..),
    chompInt,
    isDecimalDigit,
  )
where

import Data.Word (Word8)
import qualified Foreign.ForeignPtr.Unsafe as ForeignPtr
import Foreign.Ptr (Ptr)
import qualified Foreign.Ptr as Ptr
import Json.Decode.AST
  ( AST,
    AST_ (..),
    ParseError (..),
    Parser,
    StringProblem (..),
  )
import qualified Parse.Keyword as Keyword
import Parse.Primitives (Col, Row)
import qualified Parse.Primitives as Parse

-- PARSE AST

-- | Parse a complete JSON file, consuming leading and trailing whitespace.
--
-- @since 0.19.1
pFile :: Parser AST
pFile =
  do
    spaces
    value <- pValue
    spaces
    return value

-- | Parse a JSON value (object, array, string, number, or literal).
--
-- @since 0.19.1
pValue :: Parser AST
pValue =
  Parse.addLocation $
    Parse.oneOf
      Start
      [ String <$> pString Start,
        pObject,
        pArray,
        pInt,
        Keyword.k4 0x74 0x72 0x75 0x65 Start >> return TRUE,
        Keyword.k5 0x66 0x61 0x6C 0x73 0x65 Start >> return FALSE,
        Keyword.k4 0x6E 0x75 0x6C 0x6C Start >> return NULL
      ]

-- JSON OBJECT PARSING

-- | Parse JSON object @{...}@ structure.
--
-- Handles empty objects @{}@ and objects with one or more fields.
-- Processes field-value pairs separated by commas.
--
-- @since 0.19.1
pObject :: Parser AST_
pObject =
  do
    Parse.word1 0x7B {- { -} Start
    spaces
    Parse.oneOf
      ObjectField
      [ do
          entry <- pField
          spaces
          pObjectHelp [entry],
        do
          Parse.word1 0x7D {-}-} ObjectEnd
          return (Object [])
      ]

-- | Helper for parsing object continuation after first field.
--
-- Handles comma-separated additional fields and object termination.
-- Accumulates fields in reverse order for efficient list building.
--
-- @since 0.19.1
pObjectHelp ::
  -- | Accumulated fields in reverse order
  [(Parse.Snippet, AST)] ->
  -- | Complete object AST
  Parser AST_
pObjectHelp revEntries =
  Parse.oneOf
    ObjectEnd
    [ do
        Parse.word1 0x2C {-,-} ObjectEnd
        spaces
        entry <- pField
        spaces
        pObjectHelp (entry : revEntries),
      do
        Parse.word1 0x7D {-}-} ObjectEnd
        return (Object (reverse revEntries))
    ]

-- | Parse a single object field: @"key": value@.
--
-- Extracts the field name as a snippet and parses the associated value.
-- Handles colon separator and whitespace around components.
--
-- @since 0.19.1
pField :: Parser (Parse.Snippet, AST)
pField =
  do
    key <- pString ObjectField
    spaces
    Parse.word1 0x3A {-:-} ObjectColon
    spaces
    value <- pValue
    return (key, value)

-- JSON ARRAY PARSING

-- | Parse JSON array @[...]@ structure.
--
-- Handles empty arrays @[]@ and arrays with one or more elements.
-- Processes comma-separated values.
--
-- @since 0.19.1
pArray :: Parser AST_
pArray =
  do
    Parse.word1 0x5B {-[-} Start
    spaces
    Parse.oneOf
      Start
      [ do
          entry <- pValue
          spaces
          pArrayHelp 1 [entry],
        do
          Parse.word1 0x5D {-]-} ArrayEnd
          return (Array [])
      ]

-- | Helper for parsing array continuation after first element.
--
-- Handles comma-separated additional elements and array termination.
-- Tracks element count and accumulates in reverse order.
--
-- @since 0.19.1
pArrayHelp ::
  -- | Current element count
  Int ->
  -- | Accumulated elements in reverse order
  [AST] ->
  -- | Complete array AST
  Parser AST_
pArrayHelp !len revEntries =
  Parse.oneOf
    ArrayEnd
    [ do
        Parse.word1 0x2C {-,-} ArrayEnd
        spaces
        entry <- pValue
        spaces
        pArrayHelp (len + 1) (entry : revEntries),
      do
        Parse.word1 0x5D {-]-} ArrayEnd
        return (Array (reverse revEntries))
    ]

-- JSON STRING PARSING

-- | Parse JSON string with custom error context.
--
-- Handles string delimiter parsing and content extraction as a snippet.
-- Processes escape sequences and validates string syntax.
--
-- @since 0.19.1
pString ::
  -- | Error constructor for context-specific failures
  (Row -> Col -> ParseError) ->
  -- | String content as efficient snippet
  Parser Parse.Snippet
pString start =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr eerr ->
    if pos < end && Parse.unsafeIndex pos == 0x22 {-"-}
      then
        let !pos1 = Ptr.plusPtr pos 1
            !col1 = col + 1

            (# status, newPos, newRow, newCol #) =
              pStringHelp pos1 end row col1
         in case status of
              GoodString ->
                let !off = Ptr.minusPtr pos1 (ForeignPtr.unsafeForeignPtrToPtr src)
                    !len = Ptr.minusPtr newPos pos1 - 1
                    !snp = Parse.Snippet src off len row col1
                    !newState = Parse.State src newPos end indent newRow newCol
                 in cok snp newState
              BadString problem ->
                cerr newRow newCol (StringProblem problem)
      else eerr row col start

-- | Result status from string parsing.
--
-- Indicates whether string parsing succeeded or failed with specific problem.
--
-- @since 0.19.1
data StringStatus
  = -- | String parsed successfully.
    GoodString
  | -- | String parsing failed with specific problem.
    BadString !StringProblem

-- | Low-level string content parsing with escape sequence handling.
--
-- Processes string content byte-by-byte, handling escape sequences
-- and validating character constraints. Uses unboxed tuples for efficiency.
--
-- @since 0.19.1
pStringHelp ::
  -- | Current position in input
  Ptr Word8 ->
  -- | End of input buffer
  Ptr Word8 ->
  -- | Current row position
  Row ->
  -- | Current column position
  Col ->
  -- | Parse result with new position
  (# StringStatus, Ptr Word8, Row, Col #)
pStringHelp pos end row col =
  if pos >= end
    then (# BadString BadStringEnd, pos, row, col #)
    else processStringChar pos end row col

-- | Process a single character during string parsing.
--
-- Internal helper for 'pStringHelp' that classifies characters and
-- dispatches to appropriate handling logic.
--
-- @since 0.19.1
processStringChar :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> (# StringStatus, Ptr Word8, Row, Col #)
processStringChar pos end row col =
  case Parse.unsafeIndex pos of
    0x22 {-"-} -> (# GoodString, Ptr.plusPtr pos 1, row, col + 1 #)
    0x0A {-\n-} -> (# BadString BadStringEnd, pos, row, col #)
    0x5C {-\-} -> processStringEscape pos end row col
    word ->
      if word < 0x20
        then (# BadString BadStringControlChar, pos, row, col #)
        else
          let !newPos = Ptr.plusPtr pos (Parse.getCharWidth word)
           in pStringHelp newPos end row (col + 1)

-- | Process escape sequence in string parsing.
--
-- Internal helper that handles backslash-prefixed escape sequences
-- including Unicode escape validation.
--
-- @since 0.19.1
processStringEscape :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> (# StringStatus, Ptr Word8, Row, Col #)
processStringEscape pos end row col =
  let !pos1 = Ptr.plusPtr pos 1
   in if pos1 >= end
        then (# BadString BadStringEnd, pos1, row + 1, col #)
        else processEscapeChar pos1 end row col

-- | Process character after escape backslash.
--
-- Internal helper that validates and handles specific escape sequences.
--
-- @since 0.19.1
processEscapeChar :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> (# StringStatus, Ptr Word8, Row, Col #)
processEscapeChar pos1 end row col =
  case Parse.unsafeIndex pos1 of
    0x22 {-"-} -> pStringHelp (Ptr.plusPtr pos1 1) end row (col + 2)
    0x5C {-\-} -> pStringHelp (Ptr.plusPtr pos1 1) end row (col + 2)
    0x2F {-/-} -> pStringHelp (Ptr.plusPtr pos1 1) end row (col + 2)
    0x62 {-b-} -> pStringHelp (Ptr.plusPtr pos1 1) end row (col + 2)
    0x66 {-f-} -> pStringHelp (Ptr.plusPtr pos1 1) end row (col + 2)
    0x6E {-n-} -> pStringHelp (Ptr.plusPtr pos1 1) end row (col + 2)
    0x72 {-r-} -> pStringHelp (Ptr.plusPtr pos1 1) end row (col + 2)
    0x74 {-t-} -> pStringHelp (Ptr.plusPtr pos1 1) end row (col + 2)
    0x75 {-u-} -> processUnicodeEscape pos1 end row col
    _ -> (# BadString BadStringEscapeChar, Ptr.plusPtr pos1 (-1), row, col #)

-- | Process Unicode escape sequence (\uXXXX).
--
-- Internal helper that validates four hexadecimal digits
-- after Unicode escape prefix.
--
-- @since 0.19.1
processUnicodeEscape :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> (# StringStatus, Ptr Word8, Row, Col #)
processUnicodeEscape pos1 end row col =
  let !pos6 = Ptr.plusPtr pos1 5
   in if pos6 <= end
        && isHex (Parse.unsafeIndex (Ptr.plusPtr pos1 1))
        && isHex (Parse.unsafeIndex (Ptr.plusPtr pos1 2))
        && isHex (Parse.unsafeIndex (Ptr.plusPtr pos1 3))
        && isHex (Parse.unsafeIndex (Ptr.plusPtr pos1 4))
        then pStringHelp pos6 end row (col + 6)
        else (# BadString BadStringEscapeHex, Ptr.plusPtr pos1 (-1), row, col #)

-- | Check if byte represents a hexadecimal digit.
--
-- Used for validating Unicode escape sequences @\uXXXX@.
-- Accepts: @0-9@, @a-f@, @A-F@
--
-- @since 0.19.1
isHex :: Word8 -> Bool
isHex word =
  (word >= 0x30 && word <= 0x39)
    || (word >= 0x61 && word <= 0x66)
    || (word >= 0x41 && word <= 0x46)

-- WHITESPACE

-- | Parse optional whitespace (space, tab, newline, carriage return).
--
-- Handles space, tab, newline, and carriage return characters.
-- Updates position tracking for accurate error reporting.
--
-- @since 0.19.1
spaces :: Parser ()
spaces =
  Parse.Parser $ \state@(Parse.State src pos end indent row col) cok eok _ _ ->
    let (# newPos, newRow, newCol #) =
          eatSpaces pos end row col
     in if pos == newPos
          then eok () state
          else
            let !newState =
                  Parse.State src newPos end indent newRow newCol
             in cok () newState

-- | Low-level whitespace consumption with position tracking.
--
-- Efficiently skips whitespace while maintaining accurate source
-- position information for error reporting.
--
-- @since 0.19.1
eatSpaces ::
  -- | Current position in input
  Ptr Word8 ->
  -- | End of input buffer
  Ptr Word8 ->
  -- | Current row position
  Row ->
  -- | Current column position
  Col ->
  -- | New position after consuming whitespace
  (# Ptr Word8, Row, Col #)
eatSpaces pos end row col =
  if pos >= end
    then (# pos, row, col #)
    else case Parse.unsafeIndex pos of
      0x20 {-  -} -> eatSpaces (Ptr.plusPtr pos 1) end row (col + 1)
      0x09 {-\t-} -> eatSpaces (Ptr.plusPtr pos 1) end row (col + 1)
      0x0A {-\n-} -> eatSpaces (Ptr.plusPtr pos 1) end (row + 1) 1
      0x0D {-\r-} -> eatSpaces (Ptr.plusPtr pos 1) end row col
      _ ->
        (# pos, row, col #)

-- JSON INTEGER PARSING

-- | Parse JSON integer values.
--
-- Handles positive and negative integers with validation:
-- * No leading zeros (except single @0@)
-- * No floating point notation
-- * No scientific notation
--
-- @since 0.19.1
pInt :: Parser AST_
pInt =
  Parse.Parser $ \state@(Parse.State _ pos end _ row col) cok _ cerr eerr ->
    if pos >= end
      then eerr row col Start
      else parseIntDigit state cok cerr eerr

-- | Parse integer starting with first digit validation.
--
-- Internal helper for 'pInt' that validates the first digit and
-- dispatches to appropriate parsing logic.
--
-- @since 0.19.1
parseIntDigit :: Parse.State -> (AST_ -> Parse.State -> b) -> (Row -> Col -> (Row -> Col -> ParseError) -> b) -> (Row -> Col -> (Row -> Col -> ParseError) -> b) -> b
parseIntDigit state@(Parse.State _ pos _ _ row col) cok cerr eerr =
  let !word = Parse.unsafeIndex pos
   in if not (isDecimalDigit word)
        then eerr row col Start
        else
          if word == 0x30 {-0-}
            then parseZeroInt state cok cerr
            else parseNonZeroInt state word cok cerr

-- | Parse integer starting with zero.
--
-- Internal helper for 'pInt' that handles zero parsing with validation
-- for leading zeros and float detection.
--
-- @since 0.19.1
parseZeroInt :: Parse.State -> (AST_ -> Parse.State -> b) -> (Row -> Col -> (Row -> Col -> ParseError) -> b) -> b
parseZeroInt (Parse.State src pos end indent row col) cok cerr =
  let !pos1 = Ptr.plusPtr pos 1
      !newState = Parse.State src pos1 end indent row (col + 1)
   in if pos1 < end
        then validateZeroSuffix (ZeroValidationContext pos1 newState row col) cok cerr
        else cok (Int 0) newState

-- | Context for zero validation with position and state information.
--
-- Groups related parameters to reduce parameter count in validation functions.
--
-- @since 0.19.1
data ZeroValidationContext b = ZeroValidationContext
  { -- | Position after zero digit
    _zvcPos1 :: !(Ptr Word8),
    -- | New parser state
    _zvcNewState :: !Parse.State,
    -- | Current row position
    _zvcRow :: !Row,
    -- | Current column position
    _zvcCol :: !Col
  }

-- | Validate suffix after zero digit.
--
-- Internal helper that checks for invalid leading zeros or float indicators.
--
-- @since 0.19.1
validateZeroSuffix :: ZeroValidationContext b -> (AST_ -> Parse.State -> b) -> (Row -> Col -> (Row -> Col -> ParseError) -> b) -> b
validateZeroSuffix (ZeroValidationContext pos1 newState row col) cok cerr =
  let !word1 = Parse.unsafeIndex pos1
   in if isDecimalDigit word1
        then cerr row (col + 1) NoLeadingZeros
        else
          if word1 == 0x2E {-.-}
            then cerr row (col + 1) NoFloats
            else cok (Int 0) newState

-- | Parse integer starting with non-zero digit.
--
-- Internal helper for 'pInt' that handles multi-digit integer parsing.
--
-- @since 0.19.1
parseNonZeroInt :: Parse.State -> Word8 -> (AST_ -> Parse.State -> b) -> (Row -> Col -> (Row -> Col -> ParseError) -> b) -> b
parseNonZeroInt (Parse.State src pos end indent row col) word cok cerr =
  let (# status, n, newPos #) = chompInt (Ptr.plusPtr pos 1) end (fromIntegral (word - 0x30 {-0-}))
      !len = fromIntegral (Ptr.minusPtr newPos pos)
   in case status of
        GoodInt ->
          let !newState = Parse.State src newPos end indent row (col + len)
           in cok (Int n) newState
        BadIntEnd ->
          cerr row (col + len) NoFloats

-- | Result status from integer parsing.
--
-- Distinguishes successful integer parsing from floating point detection.
--
-- @since 0.19.1
data IntStatus
  = -- | Integer parsed successfully.
    GoodInt
  | -- | Found floating point indicator, integer parsing stopped.
    BadIntEnd

-- | Low-level integer digit accumulation.
--
-- Processes decimal digits and accumulates integer value.
-- Stops on floating point indicators or non-digit characters.
--
-- @since 0.19.1
chompInt ::
  -- | Current position in input
  Ptr Word8 ->
  -- | End of input buffer
  Ptr Word8 ->
  -- | Accumulated integer value
  Int ->
  -- | Parse result with final value and position
  (# IntStatus, Int, Ptr Word8 #)
chompInt pos end n =
  if pos < end
    then
      let !word = Parse.unsafeIndex pos
       in if isDecimalDigit word
            then
              let !m = 10 * n + fromIntegral (word - 0x30 {-0-})
               in chompInt (Ptr.plusPtr pos 1) end m
            else
              if word == 0x2E {-.-} || word == 0x65 {-e-} || word == 0x45 {-E-}
                then (# BadIntEnd, n, pos #)
                else (# GoodInt, n, pos #)
    else (# GoodInt, n, pos #)

-- | Check if byte represents a decimal digit (0-9).
--
-- Optimized for integer parsing performance.
--
-- @since 0.19.1
{-# INLINE isDecimalDigit #-}
isDecimalDigit :: Word8 -> Bool
isDecimalDigit word =
  word <= 0x39 {-9-} && word >= 0x30 {-0-}
