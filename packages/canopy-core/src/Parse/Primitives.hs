{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}
{-# OPTIONS_GHC -fno-warn-noncanonical-monad-instances #-}

-- | Parse.Primitives — Core parser infrastructure for the Canopy parser.
--
-- Provides the CPS (continuation-passing style) 'Parser' newtype and all
-- fundamental combinators: choice ('oneOf', 'oneOfWithFallback'), context
-- attachment ('inContext', 'specialize'), position queries ('getPosition',
-- 'getCol'), indentation management ('withIndent', 'withBacksetIndent'),
-- and low-level byte consumers ('word1', 'word2').
--
-- The parser uses four continuations: consumed-ok, empty-ok,
-- consumed-err, and empty-err.  This classic design enables efficient
-- backtracking without allocating intermediate error values.
--
-- @since 0.19.1
module Parse.Primitives
  ( fromByteString,
    Parser (..),
    State (..),
    Row,
    Col,
    oneOf,
    oneOfWithFallback,
    inContext,
    specialize,
    getPosition,
    getCol,
    addLocation,
    addEnd,
    getIndent,
    setIndent,
    withIndent,
    withBacksetIndent,
    word1,
    word2,
    unsafeIndex,
    isWord,
    getCharWidth,
    Snippet (..),
    fromSnippet,
  )
where

import qualified Control.Applicative as Applicative (Applicative (..))
import qualified Data.ByteString.Internal as BSI
import qualified Data.Text as Text
import Data.Word (Word32, Word8)
import qualified Numeric
import Foreign.ForeignPtr (ForeignPtr, touchForeignPtr)
import Foreign.ForeignPtr.Unsafe (unsafeForeignPtrToPtr)
import Foreign.Ptr (Ptr, plusPtr)
import Foreign.Storable (peek)
import qualified Reporting.Annotation as Ann
import qualified Reporting.InternalError as InternalError
import Prelude hiding (length)

-- PARSER

-- | The core parser type.
--
-- A CPS parser parameterised over an error type @x@ and result type @a@.
-- The four continuations distinguish whether input was consumed and
-- whether the result is a success or failure, enabling precise
-- backtracking semantics without allocating error values on the success
-- path.
--
-- @since 0.19.1
newtype Parser x a
  = Parser
      ( forall b.
        State ->
        (a -> State -> b) -> -- consumed ok
        (a -> State -> b) -> -- empty ok
        (Row -> Col -> (Row -> Col -> x) -> b) -> -- consumed err
        (Row -> Col -> (Row -> Col -> x) -> b) -> -- empty err
        b
      )

-- | Mutable parser state threaded through the CPS continuations.
--
-- Holds the source bytes (kept alive via the 'ForeignPtr'), the current
-- and end read positions, the active indentation level, and the current
-- source row\/column for error reporting.
--
-- @since 0.19.1
data State -- PERF try taking some out to avoid allocation
  = State
  { _src :: ForeignPtr Word8,
    _pos :: !(Ptr Word8),
    _end :: !(Ptr Word8),
    _indent :: !Word32,
    _row :: !Row,
    _col :: !Col
  }

-- | One-based source line number.
--
-- @since 0.19.1
type Row = Word32

-- | One-based source column number.
--
-- @since 0.19.1
type Col = Word32

-- FUNCTOR

instance Functor (Parser x) where
  {-# INLINE fmap #-}
  fmap f (Parser parser) =
    Parser $ \state cok eok cerr eerr ->
      let cok' a = cok (f a)
          eok' a = eok (f a)
       in parser state cok' eok' cerr eerr

-- APPLICATIVE

instance Applicative.Applicative (Parser x) where
  {-# INLINE pure #-}
  pure a = Parser (\state _cok eok _cerr _eerr -> eok a state)

  {-# INLINE (<*>) #-}
  (<*>) (Parser parserFunc) (Parser parserArg) =
    Parser $ \state cok eok cerr eerr ->
      let cokF func s1 =
            let cokA arg = cok (func arg)
             in parserArg s1 cokA cokA cerr cerr

          eokF func s1 =
            let cokA arg = cok (func arg)
                eokA arg = eok (func arg)
             in parserArg s1 cokA eokA cerr eerr
       in parserFunc state cokF eokF cerr eerr

-- ONE OF

-- | Try each parser in order, returning the first success.
--
-- If all parsers fail without consuming input, the @toError@ callback is
-- used to produce the error at the current position.  A parser that
-- consumes input before failing produces a committed error that stops
-- backtracking immediately.
--
-- @since 0.19.1
{-# INLINE oneOf #-}
oneOf :: (Row -> Col -> x) -> [Parser x a] -> Parser x a
oneOf toError parsers =
  Parser $ \state cok eok cerr eerr ->
    oneOfHelp state cok eok cerr eerr toError parsers

oneOfHelp ::
  State ->
  (a -> State -> b) ->
  (a -> State -> b) ->
  (Row -> Col -> (Row -> Col -> x) -> b) ->
  (Row -> Col -> (Row -> Col -> x) -> b) ->
  (Row -> Col -> x) ->
  [Parser x a] ->
  b
oneOfHelp state cok eok cerr eerr toError parsers =
  case parsers of
    Parser parser : parsers ->
      let eerr' _ _ _ =
            oneOfHelp state cok eok cerr eerr toError parsers
       in parser state cok eok cerr eerr'
    [] ->
      let (State _ _ _ _ row col) = state
       in eerr row col toError

-- ONE OF WITH FALLBACK

-- | Try each parser in order, returning a default value if all fail.
--
-- Like 'oneOf' but succeeds with the @fallback@ value when every parser
-- fails without consuming input, rather than returning an error.  Committed
-- failures still propagate.
--
-- @since 0.19.1
{-# INLINE oneOfWithFallback #-}
oneOfWithFallback :: [Parser x a] -> a -> Parser x a -- PERF is this function okay? Worried about allocation/laziness with fallback values.
oneOfWithFallback parsers fallback =
  Parser $ \state cok eok cerr _ ->
    oowfHelp state cok eok cerr parsers fallback

oowfHelp ::
  State ->
  (a -> State -> b) ->
  (a -> State -> b) ->
  (Row -> Col -> (Row -> Col -> x) -> b) ->
  [Parser x a] ->
  a ->
  b
oowfHelp state cok eok cerr parsers fallback =
  case parsers of
    [] ->
      eok fallback state
    Parser parser : parsers ->
      let eerr' _ _ _ =
            oowfHelp state cok eok cerr parsers fallback
       in parser state cok eok cerr eerr'

-- MONAD

instance Monad (Parser x) where
  {-# INLINE return #-}
  return value =
    Parser $ \state _ eok _ _ ->
      eok value state

  {-# INLINE (>>=) #-}
  (Parser parserA) >>= callback =
    Parser $ \state cok eok cerr eerr ->
      let cok' a s =
            case callback a of
              Parser parserB -> parserB s cok cok cerr cerr

          eok' a s =
            case callback a of
              Parser parserB -> parserB s cok eok cerr eerr
       in parserA state cok' eok' cerr eerr

-- FROM BYTESTRING

-- | Run a parser over a 'BSI.ByteString', returning 'Right' on success.
--
-- The @toBadEnd@ callback is invoked if the parser succeeds but does not
-- consume the entire input.
--
-- @since 0.19.1
fromByteString :: Parser x a -> (Row -> Col -> x) -> BSI.ByteString -> Either x a
fromByteString (Parser parser) toBadEnd (BSI.PS fptr offset length) =
  BSI.accursedUnutterablePerformIO $
    let toOk' = toOk toBadEnd
        !pos = plusPtr (unsafeForeignPtrToPtr fptr) offset
        !end = plusPtr pos length
        !result = parser (State fptr pos end 0 1 1) toOk' toOk' toErr toErr
     in do
          touchForeignPtr fptr
          return result

toOk :: (Row -> Col -> x) -> a -> State -> Either x a
toOk toBadEnd !a (State _ pos end _ row col) =
  if pos == end
    then Right a
    else Left (toBadEnd row col)

toErr :: Row -> Col -> (Row -> Col -> x) -> Either x a
toErr row col toError =
  Left (toError row col)

-- FROM SNIPPET

-- | A sub-range of a source buffer, used for doc comments and string escapes.
--
-- Preserves the original buffer pointer so the bytes can be re-parsed
-- without copying.  The @_offRow@ and @_offCol@ fields give the source
-- position of the first byte for correct error reporting.
--
-- @since 0.19.1
data Snippet = Snippet
  { _fptr :: ForeignPtr Word8,
    _offset :: Int,
    _length :: Int,
    _offRow :: Row,
    _offCol :: Col
  }
  deriving (Show)

-- | Run a parser over a pre-sliced source 'Snippet'.
--
-- Used to re-parse the content of doc comments and string literals from a
-- position already known in the source file.
--
-- @since 0.19.1
fromSnippet :: Parser x a -> (Row -> Col -> x) -> Snippet -> Either x a
fromSnippet (Parser parser) toBadEnd (Snippet fptr offset length row col) =
  BSI.accursedUnutterablePerformIO $
    let toOk' = toOk toBadEnd
        !pos = plusPtr (unsafeForeignPtrToPtr fptr) offset
        !end = plusPtr pos length
        !result = parser (State fptr pos end 0 row col) toOk' toOk' toErr toErr
     in do
          touchForeignPtr fptr
          return result

-- POSITION

-- | Return the current column number without consuming input.
--
-- @since 0.19.1
getCol :: Parser x Word32
getCol =
  Parser $ \state@(State _ _ _ _ _ col) _ eok _ _ ->
    eok col state

-- | Return the current source position (row and column) without consuming input.
--
-- @since 0.19.1
{-# INLINE getPosition #-}
getPosition :: Parser x Ann.Position
getPosition =
  Parser $ \state@(State _ _ _ _ row col) _ eok _ _ ->
    eok (Ann.Position row col) state

-- | Wrap a parser's result in a source region.
--
-- Captures the position before and after the inner parser and attaches
-- the resulting 'Ann.Region' to the value.
--
-- @since 0.19.1
addLocation :: Parser x a -> Parser x (Ann.Located a)
addLocation (Parser parser) =
  Parser $ \state@(State _ _ _ _ sr sc) cok eok cerr eerr ->
    let cok' a s@(State _ _ _ _ er ec) = cok (Ann.At (Ann.Region (Ann.Position sr sc) (Ann.Position er ec)) a) s
        eok' a s@(State _ _ _ _ er ec) = eok (Ann.At (Ann.Region (Ann.Position sr sc) (Ann.Position er ec)) a) s
     in parser state cok' eok' cerr eerr

-- | Attach a source region to a value using a known start position and the current position.
--
-- @since 0.19.1
addEnd :: Ann.Position -> a -> Parser x (Ann.Located a)
addEnd start value =
  Parser $ \state@(State _ _ _ _ row col) _ eok _ _ ->
    eok (Ann.at start (Ann.Position row col) value) state

-- INDENT

-- | Return the current indentation level without consuming input.
--
-- @since 0.19.1
getIndent :: Parser x Word32
getIndent =
  Parser $ \state@(State _ _ _ indent _ _) _ eok _ _ ->
    eok indent state

-- | Override the indentation level for subsequent parsers.
--
-- @since 0.19.1
setIndent :: Word32 -> Parser x ()
setIndent indent =
  Parser $ \(State src pos end _ row col) _ eok _ _ ->
    let !newState = State src pos end indent row col
     in eok () newState

-- | Run a parser with the indentation level set to the current column.
--
-- After the inner parser completes, the previous indentation level is
-- restored regardless of success or failure.  Used to establish the
-- indent anchor for let blocks, case alternatives, and where clauses.
--
-- @since 0.19.1
withIndent :: Parser x a -> Parser x a
withIndent (Parser parser) =
  Parser $ \(State src pos end oldIndent row col) cok eok cerr eerr ->
    let cok' a (State s p e _ r c) = cok a (State s p e oldIndent r c)
        eok' a (State s p e _ r c) = eok a (State s p e oldIndent r c)
     in parser (State src pos end col row col) cok' eok' cerr eerr

-- | Run a parser with the indentation level set to @current column - backset@.
--
-- Used for @let@ blocks where the keyword itself is 3 characters wide and
-- the definitions should align relative to the @let@ keyword position.
--
-- @since 0.19.1
withBacksetIndent :: Word32 -> Parser x a -> Parser x a
withBacksetIndent backset (Parser parser) =
  Parser $ \(State src pos end oldIndent row col) cok eok cerr eerr ->
    let cok' a (State s p e _ r c) = cok a (State s p e oldIndent r c)
        eok' a (State s p e _ r c) = eok a (State s p e oldIndent r c)
     in parser (State src pos end (col - backset) row col) cok' eok' cerr eerr

-- CONTEXT

-- | Attach outer context to all errors produced by an inner parser.
--
-- Runs @parserStart@ to consume the opening token, then runs @parserA@.
-- Any error from @parserA@ is wrapped with @addContext@ at the position
-- where the context began, enabling precise nested error messages.
--
-- @since 0.19.1
inContext :: (x -> Row -> Col -> y) -> Parser y start -> Parser x a -> Parser y a
inContext addContext (Parser parserStart) (Parser parserA) =
  Parser $ \state@(State _ _ _ _ row col) cok eok cerr eerr ->
    let cerrA r c tx = cerr row col (addContext (tx r c))
        eerrA r c tx = eerr row col (addContext (tx r c))

        cokS _ s = parserA s cok cok cerrA cerrA
        eokS _ s = parserA s cok eok cerrA eerrA
     in parserStart state cokS eokS cerr eerr

-- | Translate all errors from an inner parser using a conversion function.
--
-- Unlike 'inContext', 'specialize' does not require a leading token;
-- it simply remaps every error produced by the inner parser.
--
-- @since 0.19.1
specialize :: (x -> Row -> Col -> y) -> Parser x a -> Parser y a
specialize addContext (Parser parser) =
  Parser $ \state@(State _ _ _ _ row col) cok eok cerr eerr ->
    let cerr' r c tx = cerr row col (addContext (tx r c))
        eerr' r c tx = eerr row col (addContext (tx r c))
     in parser state cok eok cerr' eerr'

-- SYMBOLS

-- | Consume exactly one specific byte, failing with an empty error otherwise.
--
-- @since 0.19.1
word1 :: Word8 -> (Row -> Col -> x) -> Parser x ()
word1 word toError =
  Parser $ \(State src pos end indent row col) cok _ _ eerr ->
    if pos < end && unsafeIndex pos == word
      then
        let !newState = State src (plusPtr pos 1) end indent row (col + 1)
         in cok () newState
      else eerr row col toError

-- | Consume exactly two specific bytes in sequence, failing with an empty error otherwise.
--
-- @since 0.19.1
word2 :: Word8 -> Word8 -> (Row -> Col -> x) -> Parser x ()
word2 w1 w2 toError =
  Parser $ \(State src pos end indent row col) cok _ _ eerr ->
    let !pos1 = plusPtr pos 1
     in if pos1 < end && unsafeIndex pos == w1 && unsafeIndex pos1 == w2
          then
            let !newState = State src (plusPtr pos 2) end indent row (col + 2)
             in cok () newState
          else eerr row col toError

-- LOW-LEVEL CHECKS

-- | Read one byte from a pointer without bounds checking.
--
-- Callers must ensure @ptr < end@ before invoking this function.
-- Used throughout the parser for maximum throughput.
--
-- @since 0.19.1
unsafeIndex :: Ptr Word8 -> Word8
unsafeIndex ptr =
  BSI.accursedUnutterablePerformIO (peek ptr)

-- | Check that @pos < end@ and that the byte at @pos@ equals @word@.
--
-- @since 0.19.1
{-# INLINE isWord #-}
isWord :: Ptr Word8 -> Ptr Word8 -> Word8 -> Bool
isWord pos end word =
  pos < end && unsafeIndex pos == word

-- | Return the byte width of the UTF-8 character starting with @word@.
--
-- Follows the standard UTF-8 leading-byte ranges: 1 byte for ASCII
-- (@< 0x80@), 2 bytes (@0xC0–0xDF@), 3 bytes (@0xE0–0xEF@), 4 bytes
-- (@0xF0–0xF7@).  Continuation bytes (@0x80–0xBF@) and invalid leading
-- bytes report an internal error rather than silently returning 0.
--
-- @since 0.19.1
getCharWidth :: Word8 -> Int
getCharWidth word
  | word < 0x80 = 1
  | word < 0xc0 = InternalError.report
      "Parse.Primitives.getCharWidth"
      ("Invalid UTF-8 continuation byte 0x" <> showHexWord8 word <> " used as leading byte")
      "Byte values in range 0x80-0xBF are UTF-8 continuation bytes and cannot start a character. The input file may not be valid UTF-8."
  | word < 0xe0 = 2
  | word < 0xf0 = 3
  | word < 0xf8 = 4
  | otherwise = InternalError.report
      "Parse.Primitives.getCharWidth"
      ("Invalid UTF-8 leading byte 0x" <> showHexWord8 word)
      "Byte values >= 0xF8 are not valid UTF-8 leading bytes. The input file may not be valid UTF-8."

showHexWord8 :: Word8 -> Text.Text
showHexWord8 w = Text.pack (Numeric.showHex w "")
