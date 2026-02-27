{-# LANGUAGE OverloadedStrings #-}

-- | Internal AST representation for Json.Decode.
--
-- This module provides the intermediate Abstract Syntax Tree (AST) types
-- used during JSON parsing and decoding. These types are internal to the
-- Json.Decode system and not exposed in the public API.
--
-- @since 0.19.1
module Json.Decode.AST
  ( AST,
    AST_ (..),
    Parser,
    ParseError (..),
    StringProblem (..),
  )
where

import Parse.Primitives (Col, Row)
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann

-- | Annotated JSON AST node with source location.
type AST =
  Ann.Located AST_

-- | Core JSON AST node variants.
data AST_
  = Array [AST]
  | Object [(Parse.Snippet, AST)]
  | String Parse.Snippet
  | Int Int
  | TRUE
  | FALSE
  | NULL

-- | Parser type specialized for JSON parse errors.
type Parser a =
  Parse.Parser ParseError a

-- | Parse errors for JSON syntax violations.
data ParseError
  = Start Row Col
  | ObjectField Row Col
  | ObjectColon Row Col
  | ObjectEnd Row Col
  | ArrayEnd Row Col
  | StringProblem StringProblem Row Col
  | NoLeadingZeros Row Col
  | NoFloats Row Col
  | BadEnd Row Col
  deriving (Show)

-- | String-specific parse problems during JSON string processing.
data StringProblem
  = BadStringEnd
  | BadStringControlChar
  | BadStringEscapeChar
  | BadStringEscapeHex
  deriving (Show)
