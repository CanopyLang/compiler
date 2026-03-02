{-# LANGUAGE OverloadedStrings #-}

-- | Unified FFI type parser.
--
-- Single source of truth for parsing FFI type strings across the entire
-- compiler. Replaces the four independent parsers that previously existed
-- in 'FFI.Validator', 'Foreign.FFI', 'Canonicalize.Module.FFI', and
-- 'Generate.JavaScript'.
--
-- == Design
--
-- The parser uses a clean 'Token' ADT with O(n) tokenization (no list
-- append), then parses tokens into 'FFIType' from "FFI.Types". All
-- callers now go through this single parser, eliminating divergent
-- behavior and O(n²) issues.
--
-- == Usage
--
-- @
-- case parseType "Task String (List Int)" of
--   Just (FFITask FFIString (FFIList FFIInt)) -> ...
--   Nothing -> handleError
-- @
--
-- @since 0.19.2
module FFI.TypeParser
  ( -- * Parsing
    parseType,
    parseReturnType,

    -- * Arity
    countArity,

    -- * Tokenization (exposed for testing)
    Token (..),
    tokenize,
  )
where

import qualified Data.Char as Char
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Text (Text)
import FFI.Types (FFIType (..))

-- TOKEN

-- | Lexical token for FFI type strings.
--
-- 'TWord' uses 'Text' to avoid intermediate @[Char]@ allocation when
-- tokens are later converted to 'Text' for type names.
--
-- @since 0.19.2
data Token
  = TWord !Text
  | TArrow
  | TOpenParen
  | TCloseParen
  | TComma
  | TOpenBrace
  | TCloseBrace
  | TColon
  deriving (Eq, Show)

-- | Tokenize a type string into tokens.
--
-- O(n) — uses cons-based list building, no (++).
--
-- @since 0.19.2
tokenize :: Text -> [Token]
tokenize = tokenizeChars . Text.unpack

tokenizeChars :: String -> [Token]
tokenizeChars [] = []
tokenizeChars ('-' : '>' : rest) = TArrow : tokenizeChars rest
tokenizeChars ('(' : ')' : rest) = TOpenParen : TCloseParen : tokenizeChars rest
tokenizeChars ('(' : rest) = TOpenParen : tokenizeChars rest
tokenizeChars (')' : rest) = TCloseParen : tokenizeChars rest
tokenizeChars (',' : rest) = TComma : tokenizeChars rest
tokenizeChars ('{' : rest) = TOpenBrace : tokenizeChars rest
tokenizeChars ('}' : rest) = TCloseBrace : tokenizeChars rest
tokenizeChars (':' : rest) = TColon : tokenizeChars rest
tokenizeChars (c : rest)
  | Char.isSpace c = tokenizeChars rest
  | isWordStart c =
      let (word, remaining) = span isWordChar (c : rest)
       in TWord (Text.pack word) : tokenizeChars remaining
  | otherwise = tokenizeChars rest

isWordStart :: Char -> Bool
isWordStart c = Char.isAlpha c || c == '_'

isWordChar :: Char -> Bool
isWordChar c = Char.isAlphaNum c || c == '.' || c == '_'

-- PARSE

-- | Parse a type string into 'FFIType'.
--
-- Handles all FFI type patterns: primitives, parameterized types
-- (List, Maybe, Result, Task), tuples, records, function types,
-- and opaque types.
--
-- ==== Examples
--
-- >>> parseType "Int"
-- Just FFIInt
--
-- >>> parseType "List String -> Task String Bool"
-- Just (FFIFunctionType [FFIList FFIString] (FFITask FFIString FFIBool))
--
-- @since 0.19.2
parseType :: Text -> Maybe FFIType
parseType input =
  parseFunctionType (tokenize (Text.strip input))

-- | Parse and extract just the return type from a function type string.
--
-- For @"A -> B -> C"@, returns the parsed form of @"C"@.
-- For non-function types, returns the whole type.
--
-- @since 0.19.2
parseReturnType :: Text -> Maybe FFIType
parseReturnType input =
  let parts = splitAtTopLevelArrows (tokenize (Text.strip input))
   in case parts of
        [] -> Nothing
        _ -> parseBasicType (last parts)

-- FUNCTION TYPE PARSING

-- | Parse tokens that may contain top-level arrows (function type).
parseFunctionType :: [Token] -> Maybe FFIType
parseFunctionType tokens =
  let parts = splitAtTopLevelArrows tokens
   in case parts of
        [] -> Nothing
        [single] -> parseBasicType single
        multiple ->
          let argParts = init multiple
              retPart = last multiple
           in case (traverseMaybe parseBasicType argParts, parseBasicType retPart) of
                (Just args, Just ret) -> Just (FFIFunctionType args ret)
                _ -> Nothing

-- | Split tokens at top-level arrows (not inside parens/braces).
splitAtTopLevelArrows :: [Token] -> [[Token]]
splitAtTopLevelArrows tokens = finalize (go [] [] 0 tokens)
  where
    go :: [[Token]] -> [Token] -> Int -> [Token] -> ([[Token]], [Token])
    go groups current _ [] = (groups, current)
    go groups current depth (t : ts) = case t of
      TOpenParen -> go groups (t : current) (depth + 1) ts
      TCloseParen -> go groups (t : current) (max 0 (depth - 1)) ts
      TOpenBrace -> go groups (t : current) (depth + 1) ts
      TCloseBrace -> go groups (t : current) (max 0 (depth - 1)) ts
      TArrow
        | depth == 0 -> go (reverse current : groups) [] 0 ts
        | otherwise -> go groups (t : current) depth ts
      _ -> go groups (t : current) depth ts

    finalize (groups, current) = reverse (reverse current : groups)

-- BASIC TYPE PARSING

-- | Parse a non-function type (no top-level arrows).
parseBasicType :: [Token] -> Maybe FFIType
parseBasicType tokens = case tokens of
  [] -> Nothing
  -- Primitives
  [TWord "Int"] -> Just FFIInt
  [TWord "Float"] -> Just FFIFloat
  [TWord "String"] -> Just FFIString
  [TWord "Bool"] -> Just FFIBool
  [TWord "Unit"] -> Just FFIUnit
  [TOpenParen, TCloseParen] -> Just FFIUnit

  -- Parameterized types
  (TWord "List" : rest) -> FFIList <$> parseOneArg rest
  (TWord "Maybe" : rest) -> FFIMaybe <$> parseOneArg rest
  (TWord "Result" : rest) -> parseTwoArgs FFIResult rest
  (TWord "Task" : rest) -> parseTwoArgs FFITask rest

  -- Parenthesized or tuple
  (TOpenParen : rest) -> parseParenOrTuple rest

  -- Record type
  (TOpenBrace : rest) -> parseRecordType rest

  -- Single word (qualified or unqualified)
  [TWord name] -> Just (parseWordType name)

  _ -> Nothing

-- | Parse a single word into a type, handling qualified names.
--
-- Uses 'Text' operations to avoid intermediate @[Char]@ allocation.
--
-- @since 0.19.2
parseWordType :: Text -> FFIType
parseWordType name
  | Text.any (== '.') name = FFIOpaque (takeLastSegment name)
  | otherwise = FFIOpaque name
  where
    takeLastSegment = snd . Text.breakOnEnd "."

-- | Parse one type argument from remaining tokens.
parseOneArg :: [Token] -> Maybe FFIType
parseOneArg tokens =
  case takeOneTypeArg tokens of
    Just (argTokens, _) -> parseBasicType argTokens
    Nothing -> Nothing

-- | Parse two type arguments (for Result, Task).
parseTwoArgs :: (FFIType -> FFIType -> FFIType) -> [Token] -> Maybe FFIType
parseTwoArgs ctor tokens =
  case takeOneTypeArg tokens of
    Just (firstTokens, rest) ->
      case (parseBasicType firstTokens, parseBasicType rest) of
        (Just a, Just b) -> Just (ctor a b)
        _ -> Nothing
    Nothing -> Nothing

-- | Take one complete type argument from the beginning of a token list.
--
-- Handles parenthesized groups as single arguments.
takeOneTypeArg :: [Token] -> Maybe ([Token], [Token])
takeOneTypeArg [] = Nothing
takeOneTypeArg (TOpenParen : rest) =
  case takeMatchingParen rest 1 [] of
    Just (inner, remaining) -> Just (TOpenParen : reverse inner ++ [TCloseParen], remaining)
    Nothing -> Nothing
takeOneTypeArg (TWord w : rest) = Just ([TWord w], rest)
takeOneTypeArg _ = Nothing

-- | Collect tokens until the matching close paren.
takeMatchingParen :: [Token] -> Int -> [Token] -> Maybe ([Token], [Token])
takeMatchingParen [] _ _ = Nothing
takeMatchingParen (TCloseParen : rest) 1 acc = Just (acc, rest)
takeMatchingParen (TCloseParen : rest) n acc =
  takeMatchingParen rest (n - 1) (TCloseParen : acc)
takeMatchingParen (TOpenParen : rest) n acc =
  takeMatchingParen rest (n + 1) (TOpenParen : acc)
takeMatchingParen (t : rest) n acc = takeMatchingParen rest n (t : acc)

-- | Parse parenthesized expression or tuple.
parseParenOrTuple :: [Token] -> Maybe FFIType
parseParenOrTuple tokens =
  let inner = takeWhile (/= TCloseParen) tokens
      parts = splitAtTopLevelCommas inner
   in case parts of
        [[]] -> Just FFIUnit
        _ -> case traverseMaybe parseFunctionType parts of
          Just [single] -> Just single
          Just types@(_ : _ : _) -> Just (FFITuple types)
          _ -> Nothing

-- | Parse record type: @{ name : Type, age : Int }@
--
-- Rejects records with duplicate field names by returning 'Nothing'.
parseRecordType :: [Token] -> Maybe FFIType
parseRecordType tokens = do
  let inner = takeWhile (/= TCloseBrace) tokens
      fieldGroups = splitAtTopLevelCommas inner
  fields <- traverseMaybe parseRecordField fieldGroups
  if hasDuplicateFields fields then Nothing else Just (FFIRecord fields)

-- | Check for duplicate field names in a record.
hasDuplicateFields :: [(Text, a)] -> Bool
hasDuplicateFields fields =
  let names = map fst fields
   in length names /= length (nubOrd names)

-- | Remove duplicate elements preserving order (O(n log n)).
nubOrd :: (Ord a) => [a] -> [a]
nubOrd = go Set.empty
  where
    go _ [] = []
    go seen (x : xs)
      | Set.member x seen = go seen xs
      | otherwise = x : go (Set.insert x seen) xs

-- | Parse a single record field: @name : Type@
parseRecordField :: [Token] -> Maybe (Text, FFIType)
parseRecordField (TWord name : TColon : rest) =
  case parseFunctionType rest of
    Just ffiType -> Just (name, ffiType)
    Nothing -> Nothing
parseRecordField _ = Nothing

-- | Split tokens at top-level commas.
splitAtTopLevelCommas :: [Token] -> [[Token]]
splitAtTopLevelCommas tokens = finalize (go [] [] 0 tokens)
  where
    go :: [[Token]] -> [Token] -> Int -> [Token] -> ([[Token]], [Token])
    go groups current _ [] = (groups, current)
    go groups current depth (t : ts) = case t of
      TOpenParen -> go groups (t : current) (depth + 1) ts
      TCloseParen -> go groups (t : current) (max 0 (depth - 1)) ts
      TOpenBrace -> go groups (t : current) (depth + 1) ts
      TCloseBrace -> go groups (t : current) (max 0 (depth - 1)) ts
      TComma
        | depth == 0 -> go (reverse current : groups) [] 0 ts
        | otherwise -> go groups (t : current) depth ts
      _ -> go groups (t : current) depth ts

    finalize (groups, current) = reverse (reverse current : groups)

-- ARITY

-- | Count the function arity of an FFI type.
--
-- For function types, returns the number of parameters.
-- For non-function types, returns 0.
--
-- This replaces the O(n) re-tokenization approach in Generate.JavaScript
-- with a simple structural inspection of the already-parsed type.
--
-- ==== Examples
--
-- >>> countArity (FFIFunctionType [FFIInt, FFIString] FFIBool)
-- 2
--
-- >>> countArity FFIInt
-- 0
--
-- @since 0.19.2
countArity :: FFIType -> Int
countArity (FFIFunctionType params _) = length params
countArity _ = 0

-- HELPERS

-- | Traverse a list with a function that may fail.
traverseMaybe :: (a -> Maybe b) -> [a] -> Maybe [b]
traverseMaybe _ [] = Just []
traverseMaybe f (x : xs) =
  case f x of
    Nothing -> Nothing
    Just y -> (y :) <$> traverseMaybe f xs
