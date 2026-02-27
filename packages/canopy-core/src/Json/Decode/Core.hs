{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -fno-warn-noncanonical-monad-instances #-}

-- | Json.Decode.Core - Core decoder type and error types
--
-- This module defines the fundamental types for the JSON decoding framework:
-- the 'Decoder' continuation-passing type, error types, and type class
-- instances. These are shared between the main 'Json.Decode' module and
-- sub-modules like 'Json.Decode.Combinators'.
--
-- Users should import "Json.Decode" rather than this module directly.
--
-- @since 0.19.1
module Json.Decode.Core
  ( -- * Core Decoder Type
    Decoder (..),

    -- * Error Types
    Error (..),
    Problem (..),
    DecodeExpectation (..),
  )
where

import qualified Data.ByteString.Internal as BSI
import Json.Decode.AST
  ( AST,
    ParseError (..),
  )
import qualified Reporting.Annotation as Ann

-- | High-performance JSON decoder with rich error reporting.
--
-- 'Decoder' uses continuation-passing style for maximum efficiency during
-- JSON processing. The decoder takes an AST node and two continuations:
-- one for success with the decoded value, and one for failure with detailed
-- error information.
--
-- @since 0.19.1
newtype Decoder x a
  = Decoder
      ( forall b.
        AST ->
        (a -> b) ->
        (Problem x -> b) ->
        b
      )

-- | Error type combining parse failures and decode failures.
--
-- @since 0.19.1
data Error x
  = DecodeProblem BSI.ByteString (Problem x)
  | ParseProblem BSI.ByteString ParseError

deriving instance Show a => Show (Error a)

-- | Decode problem with context information.
--
-- @since 0.19.1
data Problem x
  = Field BSI.ByteString (Problem x)
  | Index Int (Problem x)
  | OneOf (Problem x) [Problem x]
  | Failure Ann.Region x
  | Expecting Ann.Region DecodeExpectation

deriving instance Show a => Show (Problem a)

-- | What type of JSON value was expected.
--
-- @since 0.19.1
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
