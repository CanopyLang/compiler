{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Rank2Types #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Json.Decode.Combinators - Object decoders and combinator decoders
--
-- This module provides object field extraction, key-value pair decoding,
-- and combinator decoders for the JSON decoding framework.
--
-- It is a sub-module of "Json.Decode" and is re-exported from there.
-- Users should import "Json.Decode" rather than this module directly.
--
-- @since 0.19.1
module Json.Decode.Combinators
  ( -- * Object Decoders
    KeyDecoder (..),
    dict,
    pairs,
    field,

    -- * Combinator Decoders
    oneOf,
    failure,
    mapError,
  )
where

import qualified Data.ByteString.Internal as BSI
import qualified Data.Map.Strict as Map
import Json.Decode.AST
  ( AST,
    AST_ (..),
  )
import Json.Decode.Core
  ( Decoder (..),
    Problem (..),
    DecodeExpectation (..),
  )
import qualified Parse.Primitives as Parse
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.InternalError as InternalError



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
-- @since 0.19.1
data KeyDecoder x a
  = -- | Key parser with error constructor for position-based failures
    KeyDecoder (Parse.Parser x a) (Row -> Col -> x)

-- | Decode a JSON object into a 'Map.Map' using key and value decoders.
--
-- @since 0.19.1
dict :: (Ord k) => KeyDecoder x k -> Decoder x a -> Decoder x (Map.Map k a)
dict keyDecoder valueDecoder =
  Map.fromList <$> pairs keyDecoder valueDecoder

-- | Decode a JSON object into a list of key-value pairs.
--
-- @since 0.19.1
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
-- provided decoder to its value.
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
-- @since 0.19.1
failure :: x -> Decoder x a
failure x =
  Decoder $ \(Ann.At region _) _ err ->
    err (Failure region x)

-- | Transform the error type of a decoder.
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
