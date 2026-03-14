{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE UnboxedTuples #-}

-- | Parse.Number — Canopy numeric literal parser.
--
-- Parses integer and floating-point literals, including hexadecimal
-- integers (@0x…@) and scientific notation (@1.5e3@).  Also provides a
-- small parser for infix operator precedence digits.
--
-- The lower-level 'chompInt' and 'chompHex' functions are exported for
-- use by the GLSL shader parser and other consumers that need numeric
-- data without the full 'Parser' wrapper.
--
-- @since 0.19.1
module Parse.Number
  ( Number (..),
    number,
    Outcome (..),
    chompInt,
    chompHex,
    precedence,
  )
where

import qualified AST.Utils.Binop as Binop
import qualified Canopy.Float as EF
import Data.Word (Word8)
import Foreign.Ptr (Ptr, minusPtr, plusPtr)
import Parse.Primitives (Col, Parser, Row)
import qualified Parse.Primitives as Parse
import qualified Parse.Variable as Var
import qualified Reporting.Error.Syntax as SyntaxError

-- HELPERS

isDirtyEnd :: Ptr Word8 -> Ptr Word8 -> Word8 -> Bool
isDirtyEnd pos end word =
  Var.getInnerWidthHelp pos end word > 0

{-# INLINE isDecimalDigit #-}
isDecimalDigit :: Word8 -> Bool
isDecimalDigit word =
  word <= 0x39 {-9-} && word >= 0x30 {-0-}

-- NUMBERS

-- | The result of parsing a numeric literal.
--
-- 'Int' carries the parsed Haskell 'Int' value; 'Float' carries the raw
-- UTF-8 bytes of the float literal for exact round-trip representation.
--
-- @since 0.19.1
data Number
  = Int Int
  | Float EF.Float

-- | Parse an integer or floating-point literal.
--
-- Accepts decimal integers, hexadecimal integers (@0x…@), and
-- floating-point literals with optional fractional and exponent parts.
-- Leading zeros followed by more digits are rejected to avoid octal
-- ambiguity.
--
-- @since 0.19.1
number :: (Row -> Col -> x) -> (SyntaxError.Number -> Row -> Col -> x) -> Parser x Number
number toExpectation toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr eerr ->
    if pos >= end
      then eerr row col toExpectation
      else
        let !word = Parse.unsafeIndex pos
         in if not (isDecimalDigit word)
              then eerr row col toExpectation
              else
                let outcome =
                      if word == 0x30 {-0-}
                        then chompZero (plusPtr pos 1) end
                        else chompInt (plusPtr pos 1) end (fromIntegral (word - 0x30 {-0-}))
                 in case outcome of
                      Err newPos problem ->
                        let !newCol = col + fromIntegral (minusPtr newPos pos)
                         in cerr row newCol (toError problem)
                      OkInt newPos n ->
                        let !newCol = col + fromIntegral (minusPtr newPos pos)
                            !integer = Int n
                            !newState = Parse.State src newPos end indent row newCol
                         in cok integer newState
                      OkFloat newPos ->
                        let !newCol = col + fromIntegral (minusPtr newPos pos)
                            !copy = EF.fromPtr pos newPos
                            !float = Float copy
                            !newState = Parse.State src newPos end indent row newCol
                         in cok float newState

-- CHOMP OUTCOME

-- | Result of the internal chomping helpers.
--
-- Carries the new read position so callers can update the column count
-- without a second scan.  'Err' signals a syntactically invalid number
-- (e.g. @0leading@, @1.e@), 'OkInt' a successfully parsed integer, and
-- 'OkFloat' a successfully parsed float (the value is read from the
-- original byte range later).
--
-- @since 0.19.1
data Outcome
  = Err (Ptr Word8) SyntaxError.Number
  | OkInt (Ptr Word8) Int
  | OkFloat (Ptr Word8)

-- CHOMP INT

-- | Accumulate a decimal integer starting from an already-consumed first digit.
--
-- Reads decimal digits, stopping at the end of input, a dot (indicating a
-- float), an @e@\/@E@ exponent, or any non-digit character.  A dirty end
-- (identifier character immediately following the number) is an error.
--
-- @since 0.19.1
chompInt :: Ptr Word8 -> Ptr Word8 -> Int -> Outcome
chompInt !pos end !n =
  if pos >= end
    then OkInt pos n
    else
      let !word = Parse.unsafeIndex pos
       in if isDecimalDigit word
            then chompInt (plusPtr pos 1) end (10 * n + fromIntegral (word - 0x30 {-0-}))
            else
              if word == 0x2E {-.-}
                then chompFraction pos end n
                else
                  if word == 0x65 {-e-} || word == 0x45 {-E-}
                    then chompExponent (plusPtr pos 1) end
                    else
                      if isDirtyEnd pos end word
                        then Err pos SyntaxError.NumberEnd
                        else OkInt pos n

-- CHOMP FRACTION

chompFraction :: Ptr Word8 -> Ptr Word8 -> Int -> Outcome
chompFraction pos end n =
  let !pos1 = plusPtr pos 1
   in if pos1 >= end
        then Err pos (SyntaxError.NumberDot n)
        else
          if isDecimalDigit (Parse.unsafeIndex pos1)
            then chompFractionHelp (plusPtr pos1 1) end
            else Err pos (SyntaxError.NumberDot n)

chompFractionHelp :: Ptr Word8 -> Ptr Word8 -> Outcome
chompFractionHelp pos end =
  if pos >= end
    then OkFloat pos
    else
      let !word = Parse.unsafeIndex pos
       in if isDecimalDigit word
            then chompFractionHelp (plusPtr pos 1) end
            else
              if word == 0x65 {-e-} || word == 0x45 {-E-}
                then chompExponent (plusPtr pos 1) end
                else
                  if isDirtyEnd pos end word
                    then Err pos SyntaxError.NumberEnd
                    else OkFloat pos

-- CHOMP EXPONENT

chompExponent :: Ptr Word8 -> Ptr Word8 -> Outcome
chompExponent pos end =
  if pos >= end
    then Err pos SyntaxError.NumberEnd
    else
      let !word = Parse.unsafeIndex pos
       in if isDecimalDigit word
            then chompExponentHelp (plusPtr pos 1) end
            else
              if word == 0x2B {-+-} || word == 0x2D {---}
                then
                  let !pos1 = plusPtr pos 1
                   in if pos1 < end && isDecimalDigit (Parse.unsafeIndex pos1)
                        then chompExponentHelp (plusPtr pos 2) end
                        else Err pos SyntaxError.NumberEnd
                else Err pos SyntaxError.NumberEnd

chompExponentHelp :: Ptr Word8 -> Ptr Word8 -> Outcome
chompExponentHelp pos end
  | pos >= end = OkFloat pos
  | isDecimalDigit (Parse.unsafeIndex pos) = chompExponentHelp (plusPtr pos 1) end
  | otherwise = OkFloat pos

-- CHOMP ZERO

chompZero :: Ptr Word8 -> Ptr Word8 -> Outcome
chompZero pos end =
  if pos >= end
    then OkInt pos 0
    else
      let !word = Parse.unsafeIndex pos
       in if word == 0x78 {-x-}
            then chompHexInt (plusPtr pos 1) end
            else
              if word == 0x2E {-.-}
                then chompFraction pos end 0
                else
                  if isDecimalDigit word
                    then Err pos SyntaxError.NumberNoLeadingZero
                    else
                      if isDirtyEnd pos end word
                        then Err pos SyntaxError.NumberEnd
                        else OkInt pos 0

chompHexInt :: Ptr Word8 -> Ptr Word8 -> Outcome
chompHexInt pos end =
  let (# newPos, answer #) = chompHex pos end
   in if answer < 0
        then Err newPos SyntaxError.NumberHexDigit
        else OkInt newPos answer

-- CHOMP HEX

-- | Chomp a hexadecimal digit sequence and return the accumulated value.
--
-- Returns @-1@ when no hex digits are found and @-2@ when an invalid
-- character (not a hex digit but still an identifier character) is
-- encountered.  Exported for use by the GLSL shader parser.
--
-- @since 0.19.1
{-# INLINE chompHex #-}
chompHex :: Ptr Word8 -> Ptr Word8 -> (# Ptr Word8, Int #)
chompHex pos end =
  chompHexHelp pos end (-1) 0

chompHexHelp :: Ptr Word8 -> Ptr Word8 -> Int -> Int -> (# Ptr Word8, Int #)
chompHexHelp pos end answer accumulator =
  if pos >= end
    then (# pos, answer #)
    else
      let !newAnswer =
            stepHex pos end (Parse.unsafeIndex pos) accumulator
       in if newAnswer < 0
            then (# pos, if newAnswer == -1 then answer else -2 #)
            else chompHexHelp (plusPtr pos 1) end newAnswer newAnswer

{-# INLINE stepHex #-}
stepHex :: Ptr Word8 -> Ptr Word8 -> Word8 -> Int -> Int
stepHex pos end word acc
  | 0x30 {-0-} <= word && word <= 0x39 {-9-} = 16 * acc + fromIntegral (word - 0x30 {-0-})
  | 0x61 {-a-} <= word && word <= 0x66 {-f-} = 16 * acc + 10 + fromIntegral (word - 0x61 {-a-})
  | 0x41 {-A-} <= word && word <= 0x46 {-F-} = 16 * acc + 10 + fromIntegral (word - 0x41 {-A-})
  | isDirtyEnd pos end word = -2
  | otherwise = -1

-- PRECEDENCE

-- | Parse a single decimal digit as a binary operator precedence level (0–9).
--
-- Used by the module parser when reading @infix@ declarations.
-- Only a single digit is consumed; multi-digit values are not valid Canopy
-- precedences.
--
-- @since 0.19.1
precedence :: (Row -> Col -> x) -> Parser x Binop.Precedence
precedence toExpectation =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    if pos >= end
      then eerr row col toExpectation
      else
        let !word = Parse.unsafeIndex pos
         in if isDecimalDigit word
              then
                cok
                  (Binop.Precedence (fromIntegral (word - 0x30 {-0-})))
                  (Parse.State src (plusPtr pos 1) end indent row (col + 1))
              else eerr row col toExpectation
