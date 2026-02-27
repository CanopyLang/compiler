{-# LANGUAGE OverloadedStrings #-}

-- | FFI Runtime Validation
--
-- This module generates JavaScript validators for FFI type boundaries.
-- These validators ensure type safety at runtime when calling JavaScript
-- functions from Canopy code.
--
-- = Usage
--
-- In strict FFI mode (@--ffi-strict@), the generated JavaScript includes
-- runtime type checks for FFI function return values:
--
-- @
-- function validateInt(v, name) {
--   if (!Number.isInteger(v)) {
--     throw new Error('FFI type error: ' + name + ' expected Int, got ' + typeof v);
--   }
--   return v;
-- }
-- @
--
-- = Validation Strategy
--
-- * Primitive types: Direct typeof/Number.isInteger checks
-- * List types: Array.isArray + recursive element validation
-- * Maybe types: null check + value validation
-- * Result types: Structure check ($: 'Ok' | 'Err') + field validation
-- * Task types: Promise check + result validation on resolution
-- * Opaque types: Optional instanceof check (configurable)
--
-- @since 0.19.1
module FFI.Validator
  ( -- * Validator generation
    generateValidator
  , generateValidatorName
  , generateAllValidators
  , ValidatorConfig(..)
  , defaultConfig

    -- * FFI type representation (re-exported from FFI.Types)
  , FFIType(..)

    -- * Type string parsing
  , parseFFIType
  , parseReturnType
  ) where

import qualified Data.Char as Char
import qualified Data.Text as Text
import Data.Text (Text)
import FFI.Types (FFIType (..))

-- | Configuration for validator generation
data ValidatorConfig = ValidatorConfig
  { _configStrictMode :: !Bool
    -- ^ Enable strict validation (throws on type mismatch)
  , _configValidateOpaque :: !Bool
    -- ^ Validate opaque types with instanceof checks
  , _configDebugMode :: !Bool
    -- ^ Include debug information in error messages
  } deriving (Eq, Show)

-- | Default validator configuration
defaultConfig :: ValidatorConfig
defaultConfig = ValidatorConfig
  { _configStrictMode = True
  , _configValidateOpaque = False
  , _configDebugMode = False
  }

-- FFIType is imported from FFI.Types (single source of truth)

-- | Generate a unique validator name for a type
generateValidatorName :: FFIType -> Text
generateValidatorName ffiType = "_validate_" <> typeToSuffix ffiType
  where
    typeToSuffix :: FFIType -> Text
    typeToSuffix t = case t of
      FFIInt -> "Int"
      FFIFloat -> "Float"
      FFIString -> "String"
      FFIBool -> "Bool"
      FFIUnit -> "Unit"
      FFIList inner -> "List_" <> typeToSuffix inner
      FFIMaybe inner -> "Maybe_" <> typeToSuffix inner
      FFIResult e v -> "Result_" <> typeToSuffix e <> "_" <> typeToSuffix v
      FFITask e v -> "Task_" <> typeToSuffix e <> "_" <> typeToSuffix v
      FFITuple types -> "Tuple_" <> Text.intercalate "_" (map typeToSuffix types)
      FFIOpaque name -> "Opaque_" <> sanitizeName name
      FFIFunctionType _ ret -> "Fn_" <> typeToSuffix ret
      FFIRecord fields -> "Rec_" <> Text.intercalate "_" (map (sanitizeName . fst) fields)

    sanitizeName :: Text -> Text
    sanitizeName = Text.filter (\c -> c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9')

-- | Generate JavaScript validator function for an FFI type
generateValidator :: ValidatorConfig -> FFIType -> Text
generateValidator config ffiType =
  let name = generateValidatorName ffiType
      body = generateValidatorBody config ffiType
  in Text.unlines
       [ "function " <> name <> "(v, ctx) {"
       , body
       , "}"
       ]

-- | Generate the body of a validator function
generateValidatorBody :: ValidatorConfig -> FFIType -> Text
generateValidatorBody config ffiType = case ffiType of
  FFIInt ->
    indent <> "if (!Number.isInteger(v)) {\n"
    <> indent <> "  " <> throwError config "Int" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIFloat ->
    indent <> "if (typeof v !== 'number') {\n"
    <> indent <> "  " <> throwError config "Float" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIString ->
    indent <> "if (typeof v !== 'string') {\n"
    <> indent <> "  " <> throwError config "String" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIBool ->
    indent <> "if (typeof v !== 'boolean') {\n"
    <> indent <> "  " <> throwError config "Bool" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIUnit ->
    indent <> "return v;"

  FFIList inner ->
    let innerValidator = generateValidatorName inner
    in indent <> "if (!Array.isArray(v)) {\n"
       <> indent <> "  " <> throwError config "List" <> "\n"
       <> indent <> "}\n"
       <> indent <> "return v.map(function(el, i) { return " <> innerValidator <> "(el, ctx + '[' + i + ']'); });"

  FFIMaybe inner ->
    let innerValidator = generateValidatorName inner
    in indent <> "if (v == null) { return { $: 'Nothing' }; }\n"
       <> indent <> "return { $: 'Just', a: " <> innerValidator <> "(v, ctx) };"

  FFIResult errType valType ->
    let errValidator = generateValidatorName errType
        valValidator = generateValidatorName valType
    in indent <> "if (typeof v !== 'object' || v === null || !('$' in v)) {\n"
       <> indent <> "  " <> throwError config "Result" <> "\n"
       <> indent <> "}\n"
       <> indent <> "if (v.$ === 'Ok') {\n"
       <> indent <> "  return { $: 'Ok', a: " <> valValidator <> "(v.a, ctx + '.Ok') };\n"
       <> indent <> "} else if (v.$ === 'Err') {\n"
       <> indent <> "  return { $: 'Err', a: " <> errValidator <> "(v.a, ctx + '.Err') };\n"
       <> indent <> "}\n"
       <> indent <> throwError config "Result (invalid $)"

  FFITask errType valType ->
    let errValidator = generateValidatorName errType
        valValidator = generateValidatorName valType
    in indent <> "if (typeof v !== 'object' || v === null || typeof v.then !== 'function') {\n"
       <> indent <> "  " <> throwError config "Task (expected Promise)" <> "\n"
       <> indent <> "}\n"
       <> indent <> "return v.then(\n"
       <> indent <> "  function(ok) { return { $: 'Ok', a: " <> valValidator <> "(ok, ctx + '.then') }; },\n"
       <> indent <> "  function(err) { return { $: 'Err', a: " <> errValidator <> "(err, ctx + '.catch') }; }\n"
       <> indent <> ");"

  FFITuple types ->
    let validators = map generateValidatorName types
        checks = zipWith (\idx vn -> vn <> "(v[" <> Text.pack (show (idx :: Int)) <> "], ctx + '[" <> Text.pack (show idx) <> "]')") [0..] validators
    in indent <> "if (!Array.isArray(v) || v.length !== " <> Text.pack (show (length types)) <> ") {\n"
       <> indent <> "  " <> throwError config ("Tuple" <> Text.pack (show (length types))) <> "\n"
       <> indent <> "}\n"
       <> indent <> "return [" <> Text.intercalate ", " checks <> "];"

  FFIOpaque typeName ->
    if _configValidateOpaque config
      then indent <> "if (!(v instanceof " <> typeName <> ")) {\n"
           <> indent <> "  " <> throwError config typeName <> "\n"
           <> indent <> "}\n"
           <> indent <> "return v;"
      else indent <> "return v; // Opaque type: " <> typeName

  FFIFunctionType _ _ ->
    indent <> "if (typeof v !== 'function') {\n"
    <> indent <> "  " <> throwError config "Function" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIRecord fields ->
    indent <> "if (typeof v !== 'object' || v === null) {\n"
    <> indent <> "  " <> throwError config "Record" <> "\n"
    <> indent <> "}\n"
    <> Text.concat (map validateField fields)
    <> indent <> "return v;"

  where
    validateField (name, fieldType) =
      indent <> generateValidatorName fieldType <> "(v." <> name <> ", ctx + '." <> name <> "');\n"
    indent = "  "

-- | Generate error throwing statement
throwError :: ValidatorConfig -> Text -> Text
throwError config expectedType =
  if _configStrictMode config
    then if _configDebugMode config
           then "throw new Error('FFI type error at ' + ctx + ': expected " <> expectedType <> ", got ' + typeof v + ': ' + JSON.stringify(v));"
           else "throw new Error('FFI type error at ' + ctx + ': expected " <> expectedType <> ", got ' + typeof v);"
    else "console.warn('FFI type warning at ' + ctx + ': expected " <> expectedType <> ", got ' + typeof v);"

-- | Generate all required validators for a type and its nested types
generateAllValidators :: ValidatorConfig -> FFIType -> Text
generateAllValidators config ffiType =
  Text.unlines (map (generateValidator config) (collectTypes ffiType))
  where
    collectTypes :: FFIType -> [FFIType]
    collectTypes t = t : concatMap collectTypes (childTypes t)

    childTypes :: FFIType -> [FFIType]
    childTypes ty = case ty of
      FFIList inner -> [inner]
      FFIMaybe inner -> [inner]
      FFIResult e v -> [e, v]
      FFITask e v -> [e, v]
      FFITuple types -> types
      FFIFunctionType args ret -> args ++ [ret]
      FFIRecord fields -> map snd fields
      _ -> []

-- | Parse a type string into FFIType
parseFFIType :: Text -> Maybe FFIType
parseFFIType input =
  let tokens = tokenize (Text.unpack (Text.strip input))
  in parseTokens tokens

-- | Parse and extract just the return type from a function type string
parseReturnType :: Text -> Maybe FFIType
parseReturnType input =
  let tokens = tokenize (Text.unpack (Text.strip input))
      parts = splitAtArrows tokens
  in case parts of
    [] -> Nothing
    _ -> parseTokens (last parts)

-- | Token type for parsing
data Token
  = TWord String
  | TArrow
  | TOpenParen
  | TCloseParen
  | TComma
  deriving (Eq, Show)

-- | Tokenize a type string
tokenize :: String -> [Token]
tokenize [] = []
tokenize ('-':'>':rest) = TArrow : tokenize rest
tokenize ('(':rest) = TOpenParen : tokenize rest
tokenize (')':rest) = TCloseParen : tokenize rest
tokenize (',':rest) = TComma : tokenize rest
tokenize (c:rest)
  | Char.isSpace c = tokenize rest
  | Char.isAlpha c || c == '.' =
      let (word, remaining) = span isWordChar (c:rest)
      in TWord word : tokenize remaining
  | otherwise = tokenize rest
  where
    isWordChar ch = Char.isAlphaNum ch || ch == '.' || ch == '_'

-- | Split tokens at top-level arrows
splitAtArrows :: [Token] -> [[Token]]
splitAtArrows tokens = go [] [] (0 :: Int) tokens
  where
    go groups current _ [] = reverse (reverse current : groups)
    go groups current depth (t:ts) = case t of
      TOpenParen -> go groups (t:current) (depth + 1) ts
      TCloseParen -> go groups (t:current) (max 0 (depth - 1)) ts
      TArrow
        | depth == 0 -> go (reverse current : groups) [] 0 ts
        | otherwise -> go groups (t:current) depth ts
      _ -> go groups (t:current) depth ts

-- | Parse tokens into FFIType
parseTokens :: [Token] -> Maybe FFIType
parseTokens tokens =
  case tokens of
    [] -> Nothing
    [TWord "Int"] -> Just FFIInt
    [TWord "Float"] -> Just FFIFloat
    [TWord "String"] -> Just FFIString
    [TWord "Bool"] -> Just FFIBool
    [TWord "()"] -> Just FFIUnit
    [TWord name] -> Just (FFIOpaque (Text.pack name))

    -- List a
    (TWord "List" : rest) ->
      FFIList <$> parseTokens rest

    -- Maybe a
    (TWord "Maybe" : rest) ->
      FFIMaybe <$> parseTokens rest

    -- Result e a
    (TWord "Result" : rest) ->
      parseResultType rest

    -- Task e a
    (TWord "Task" : rest) ->
      parseTaskType rest

    -- Tuple (a, b, ...)
    (TOpenParen : rest) ->
      parseTupleType rest

    -- Function type
    _ | hasTopLevelArrow tokens ->
      parseFunctionType tokens

    _ -> Nothing

-- | Check if tokens contain a top-level arrow (not inside parentheses)
hasTopLevelArrow :: [Token] -> Bool
hasTopLevelArrow = go (0 :: Int)
  where
    go _ [] = False
    go depth (t:ts) = case t of
      TOpenParen -> go (depth + 1) ts
      TCloseParen -> go (max 0 (depth - 1)) ts
      TArrow | depth == 0 -> True
      _ -> go depth ts

-- | Parse Result e a type
parseResultType :: [Token] -> Maybe FFIType
parseResultType tokens =
  let (errTokens, rest) = takeTypeArg tokens
  in case (parseTokens errTokens, parseTokens rest) of
    (Just errType, Just valType) -> Just (FFIResult errType valType)
    _ -> Nothing

-- | Parse Task e a type
parseTaskType :: [Token] -> Maybe FFIType
parseTaskType tokens =
  let (errTokens, rest) = takeTypeArg tokens
  in case (parseTokens errTokens, parseTokens rest) of
    (Just errType, Just valType) -> Just (FFITask errType valType)
    _ -> Nothing

-- | Parse tuple type (a, b, ...) or parenthesized expression (a) or unit ()
parseTupleType :: [Token] -> Maybe FFIType
parseTupleType tokens =
  let inner = takeWhile (/= TCloseParen) tokens
      parts = splitAtCommas inner
  in case parts of
    [[]] -> Just FFIUnit  -- Empty parens () is Unit type
    _ -> case traverseMaybe parseTokens parts of
      Just [singleType] -> Just singleType  -- Parenthesized expression, not 1-tuple
      Just types -> Just (FFITuple types)
      Nothing -> Nothing

-- | Parse function type a -> b -> c
parseFunctionType :: [Token] -> Maybe FFIType
parseFunctionType tokens =
  let parts = splitAtArrows tokens
  in case parts of
    [] -> Nothing
    [single] -> parseTokens single
    _ ->
      let argParts = init parts
          retPart = last parts
      in case (traverseMaybe parseTokens argParts, parseTokens retPart) of
        (Just args, Just ret) -> Just (FFIFunctionType args ret)
        _ -> Nothing

-- | Take one type argument from token list
takeTypeArg :: [Token] -> ([Token], [Token])
takeTypeArg [] = ([], [])
takeTypeArg (TOpenParen : rest) =
  let (inside, remaining) = takeParenthesized rest 1 []
  in (TOpenParen : inside ++ [TCloseParen], remaining)
takeTypeArg (TWord w : rest) = ([TWord w], rest)
takeTypeArg tokens = ([], tokens)

-- | Take tokens inside parentheses
takeParenthesized :: [Token] -> Int -> [Token] -> ([Token], [Token])
takeParenthesized [] _ acc = (reverse acc, [])
takeParenthesized (TCloseParen : rest) 1 acc = (reverse acc, rest)
takeParenthesized (TCloseParen : rest) n acc =
  takeParenthesized rest (n - 1) (TCloseParen : acc)
takeParenthesized (TOpenParen : rest) n acc =
  takeParenthesized rest (n + 1) (TOpenParen : acc)
takeParenthesized (t : rest) n acc = takeParenthesized rest n (t : acc)

-- | Split tokens at commas (top-level only)
splitAtCommas :: [Token] -> [[Token]]
splitAtCommas tokens = go [] [] (0 :: Int) tokens
  where
    go groups current _ [] = reverse (reverse current : groups)
    go groups current depth (t:ts) = case t of
      TOpenParen -> go groups (t:current) (depth + 1) ts
      TCloseParen -> go groups (t:current) (max 0 (depth - 1)) ts
      TComma
        | depth == 0 -> go (reverse current : groups) [] 0 ts
        | otherwise -> go groups (t:current) depth ts
      _ -> go groups (t:current) depth ts

-- | Traverse helper for Maybe
traverseMaybe :: (a -> Maybe b) -> [a] -> Maybe [b]
traverseMaybe _ [] = Just []
traverseMaybe f (x:xs) =
  case f x of
    Nothing -> Nothing
    Just y -> (y :) <$> traverseMaybe f xs
