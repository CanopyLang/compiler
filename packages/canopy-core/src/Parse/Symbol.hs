{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Parse.Symbol — Canopy operator symbol parser.
--
-- Parses infix operator tokens (@+@, @|>@, @<*>@, etc.) from the source
-- stream and rejects reserved punctuation that must not appear as
-- user-defined operators.
--
-- @since 0.19.1
module Parse.Symbol
  ( operator,
    BadOperator (..),
    binopCharSet,
  )
where

import qualified Data.Char as Char
import qualified Data.IntSet as IntSet
import qualified Canopy.Data.Name as Name
import qualified Data.Vector as Vector
import Foreign.Ptr (Ptr, minusPtr, plusPtr)
import GHC.Word (Word8)
import Parse.Primitives (Col, Parser, Row)
import qualified Parse.Primitives as Parse

-- OPERATOR

-- | Reason an operator token was rejected as invalid.
--
-- Each variant names a specific reserved punctuation sequence that must
-- not be used as a user-defined operator symbol.
--
-- @since 0.19.1
data BadOperator
  = BadDot
  | BadPipe
  | BadArrow
  | BadEquals
  | BadHasType
  deriving (Eq, Show)

-- | Parse an infix operator symbol, rejecting reserved punctuation.
--
-- Consumes as many 'binopCharSet' characters as possible, then checks
-- whether the resulting token is one of the reserved sequences (@.@,
-- @|@, @->@, @=@, @:@). Reserved sequences produce a committed error
-- using the @toError@ callback; an empty match produces an empty error
-- using @toExpectation@.
--
-- @since 0.19.1
operator :: (Row -> Col -> x) -> (BadOperator -> Row -> Col -> x) -> Parser x Name.Name
operator toExpectation toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr eerr ->
    let !newPos = chompOps pos end
     in if pos == newPos
          then eerr row col toExpectation
          else case Name.fromPtr pos newPos of
            "." -> eerr row col (toError BadDot)
            "|" -> cerr row col (toError BadPipe)
            "->" -> cerr row col (toError BadArrow)
            "=" -> cerr row col (toError BadEquals)
            ":" -> cerr row col (toError BadHasType)
            op ->
              let !newCol = col + fromIntegral (minusPtr newPos pos)
                  !newState = Parse.State src newPos end indent row newCol
               in cok op newState

chompOps :: Ptr Word8 -> Ptr Word8 -> Ptr Word8
chompOps pos end =
  if pos < end && isBinopCharHelp (Parse.unsafeIndex pos)
    then chompOps (plusPtr pos 1) end
    else pos

{-# INLINE isBinopCharHelp #-}
isBinopCharHelp :: Word8 -> Bool
isBinopCharHelp word =
  word < 128 && Vector.unsafeIndex binopCharVector (fromIntegral word)

{-# NOINLINE binopCharVector #-}
binopCharVector :: Vector.Vector Bool
binopCharVector =
  Vector.generate 128 (\i -> IntSet.member i binopCharSet)

-- | The set of ASCII codepoints that may appear in an operator symbol.
--
-- Contains all characters from @+-\/*=.<>:&|^?%!@.  Exported so that
-- other modules (e.g. "Parse.Number") can detect whether a character
-- immediately after a numeric literal would form an operator.
--
-- @since 0.19.1
{-# NOINLINE binopCharSet #-}
binopCharSet :: IntSet.IntSet
binopCharSet =
  IntSet.fromList (fmap Char.ord "+-/*=.<>:&|^?%!")
