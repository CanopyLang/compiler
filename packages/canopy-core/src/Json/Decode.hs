{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE StandaloneDeriving #-}
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
-- * Core types - See "Json.Decode.Core" for the Decoder newtype
-- * Combinators - See "Json.Decode.Combinators" for object/combinator decoders
--
-- Error reporting integrates with "Reporting.Annotation" for consistent
-- formatting across the compiler pipeline.
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
import qualified Canopy.Data.NonEmptyList as NE
import qualified Json.String as Json
import Json.Decode.AST
  ( AST,
    AST_ (..),
    ParseError (..),
    StringProblem (..),
  )
import Json.Decode.Combinators
  ( KeyDecoder (..),
    dict,
    failure,
    field,
    mapError,
    oneOf,
    pairs,
  )
import Json.Decode.Core
  ( Decoder (..),
    DecodeExpectation (..),
    Error (..),
    Problem (..),
  )
import Json.Decode.Parser (pFile)
import qualified Parse.Primitives as Parse
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann

-- MAIN DECODING INTERFACE

-- | Decode a JSON value from a ByteString using the specified decoder.
--
-- This is the main entry point for JSON decoding. It parses the ByteString
-- into an intermediate AST, then applies the decoder to extract the desired
-- value with comprehensive error reporting.
--
-- @since 0.19.1
fromByteString :: Decoder x a -> BSI.ByteString -> Either (Error x) a
fromByteString (Decoder decode) src =
  case Parse.fromByteString pFile BadEnd src of
    Right ast ->
      decode ast Right (Left . DecodeProblem src)
    Left problem ->
      Left (ParseProblem src problem)

-- PRIMITIVE VALUE DECODERS

-- | Decode a JSON string into a 'Json.String'.
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

-- | Decode a JSON string using a custom parser.
--
-- @since 0.19.1
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
