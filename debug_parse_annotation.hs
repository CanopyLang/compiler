#!/usr/bin/env stack
{- stack
  script
  --resolver lts-22.30
  --package text
-}

{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text

-- Copy the exact tokenization and parsing logic from FFI.hs

-- Data types
data FFIType
  = FFIBasic Text.Text
  | FFIOpaque Text.Text
  | FFIFunctionType [FFIType] FFIType
  | FFITask FFIType FFIType
  | FFIMaybe FFIType
  | FFIList FFIType
  | FFIResult FFIType FFIType
  deriving (Show, Eq)

tokenizeCanopyType :: Text.Text -> [Text.Text]
tokenizeCanopyType typeText = filter (not . Text.null) (go [] "" typeText)
  where
    go :: [Text.Text] -> Text.Text -> Text.Text -> [Text.Text]
    go acc current text
      | Text.null text = if Text.null current then acc else acc ++ [current]
      | Text.head text == '(' =
          let newAcc = if Text.null current then acc else acc ++ [current]
          in go (newAcc ++ ["("]) "" (Text.tail text)
      | Text.head text == ')' =
          let newAcc = if Text.null current then acc else acc ++ [current]
          in go (newAcc ++ [")"]) "" (Text.tail text)
      | Text.head text == ' ' =
          if Text.null current
            then go acc "" (Text.tail text)
            else go (acc ++ [current]) "" (Text.tail text)
      | otherwise =
          go acc (current <> Text.take 1 text) (Text.tail text)

parseCanopyTypeAnnotation :: Text.Text -> Maybe FFIType
parseCanopyTypeAnnotation typeText =
  let tokens = tokenizeCanopyType typeText
      cleanedTokens = filter (not . Text.null) tokens
  in if null cleanedTokens
       then Nothing
       else parseFFIType cleanedTokens

parseFFIType :: [Text.Text] -> Maybe FFIType
parseFFIType tokens = parseFunction (stripOuterParens tokens)
  where
    stripOuterParens :: [Text.Text] -> [Text.Text]
    stripOuterParens ts = case ts of
      "(" : rest -> case matchingParen rest 0 of
        Just (inner, []) -> inner
        _ -> ts
      _ -> ts

    matchingParen :: [Text.Text] -> Int -> Maybe ([Text.Text], [Text.Text])
    matchingParen [] _ = Nothing
    matchingParen (t:ts) depth
      | t == "(" = do
          (inner, remaining) <- matchingParen ts (depth + 1)
          pure (t : inner, remaining)
      | t == ")" =
          if depth == 0
            then Just ([], ts)
            else do
              (inner, remaining) <- matchingParen ts (depth - 1)
              pure (t : inner, remaining)
      | otherwise = do
          (inner, remaining) <- matchingParen ts depth
          pure (t : inner, remaining)

    parseFunction :: [Text.Text] -> Maybe FFIType
    parseFunction ts = case findFunctionArrow ts of
      Nothing -> parseBasicType ts
      Just (paramTokens, restTokens) -> do
        case parseFunction restTokens of
          Just returnType ->
            if paramTokens == ["(", ")"] || paramTokens == ["()"]
              then Just returnType
              else do
                paramType <- parseBasicType paramTokens
                Just (extendFunction paramType returnType)
          Nothing -> parseBasicType paramTokens

    findFunctionArrow :: [Text.Text] -> Maybe ([Text.Text], [Text.Text])
    findFunctionArrow ts = go [] (0 :: Int) ts
      where
        go _ _ [] = Nothing
        go acc parenCount (t:rest)
          | t == "(" = go (acc ++ [t]) (parenCount + 1) rest
          | t == ")" = go (acc ++ [t]) (parenCount - 1) rest
          | t == "->" && parenCount == 0 = Just (acc, rest)
          | otherwise = go (acc ++ [t]) parenCount rest

    extendFunction :: FFIType -> FFIType -> FFIType
    extendFunction paramType (FFIFunctionType params returnType) =
      FFIFunctionType (paramType : params) returnType
    extendFunction paramType returnType =
      FFIFunctionType [paramType] returnType

    parseBasicType :: [Text.Text] -> Maybe FFIType
    parseBasicType ts = case ts of
      [] -> Nothing
      ["String"] -> Just (FFIBasic "String")
      ["Int"] -> Just (FFIBasic "Int")
      ["Bool"] -> Just (FFIBasic "Bool")
      ["Float"] -> Just (FFIBasic "Float")
      ["()"] -> Just (FFIBasic "()")
      ["(", ")"] -> Just (FFIBasic "Unit")

      ("Task" : rest) -> parseTaskType rest
      ("Maybe" : rest) -> parseMaybeType rest
      ("List" : rest) -> parseListType rest
      ("Result" : rest) -> parseResultType rest

      parenTs@("(" : _) -> parseParenthesized parenTs

      [typeName] | not (typeName `elem` reservedTypes) ->
        Just (FFIOpaque typeName)

      multiWordType | length multiWordType > 1 && not (any (`elem` reservedTypes) multiWordType) ->
        Just (FFIOpaque (Text.unwords multiWordType))

      _ -> Nothing

    parseParenthesized :: [Text.Text] -> Maybe FFIType
    parseParenthesized ts = case ts of
      "(" : rest -> case break (== ")") rest of
        (innerTokens, ")" : _) -> parseBasicType innerTokens
        _ -> Nothing
      _ -> Nothing

    parseTaskType :: [Text.Text] -> Maybe FFIType
    parseTaskType ts = case splitTypeArguments ts of
      [errorTokens, valueTokens] -> do
        errorFFI <- parseBasicType errorTokens
        valueFFI <- parseBasicType valueTokens
        Just (FFITask errorFFI valueFFI)
      _ -> Nothing

    parseMaybeType :: [Text.Text] -> Maybe FFIType
    parseMaybeType ts = case splitTypeArguments ts of
      [valueTokens] -> do
        valueFFI <- parseBasicType valueTokens
        Just (FFIMaybe valueFFI)
      _ -> Nothing

    parseListType :: [Text.Text] -> Maybe FFIType
    parseListType ts = case splitTypeArguments ts of
      [elementTokens] -> do
        elementFFI <- parseBasicType elementTokens
        Just (FFIList elementFFI)
      _ -> Nothing

    parseResultType :: [Text.Text] -> Maybe FFIType
    parseResultType ts = case splitTypeArguments ts of
      [errorTokens, valueTokens] -> do
        errorFFI <- parseBasicType errorTokens
        valueFFI <- parseBasicType valueTokens
        Just (FFIResult errorFFI valueFFI)
      _ -> Nothing

    -- Use the same improved splitTypeArguments logic as the actual compiler
    splitTypeArguments :: [Text.Text] -> [[Text.Text]]
    splitTypeArguments ts = splitTypes ts []
      where
        splitTypes [] acc = reverse acc
        splitTypes tokens acc =
          case takeOneType tokens of
            Just (typeTokens, remainingTokens) ->
              splitTypes remainingTokens (typeTokens : acc)
            Nothing -> reverse acc

        takeOneType [] = Nothing
        takeOneType tokens@(t:_)
          | t == "(" = takeParenthesizedType tokens
          | otherwise = takeSingleOrMultiWordType tokens

        takeParenthesizedType ("(" : rest) =
          case findMatchingParen rest 0 of
            Just (inner, ")" : remaining) -> Just ("(" : inner ++ [")"], remaining)
            _ -> Nothing
        takeParenthesizedType _ = Nothing

        takeSingleOrMultiWordType [] = Nothing
        takeSingleOrMultiWordType (t:ts)
          | t `elem` reservedTypes = Just ([t], ts)
          | otherwise =
              case takeMultiWordType (t:ts) of
                (typeTokens@(_:_), remaining) -> Just (typeTokens, remaining)
                ([], _) -> Just ([t], ts)

        takeMultiWordType tokens = go [] tokens
          where
            go acc [] = (reverse acc, [])
            go acc (t:ts)
              | t `elem` reservedTypes = (reverse acc, t:ts)
              | t `elem` ["(", ")"] = (reverse acc, t:ts)
              | otherwise = go (t:acc) ts

        findMatchingParen [] _ = Nothing
        findMatchingParen (t:ts) depth
          | t == "(" = do
              (inner, remaining) <- findMatchingParen ts (depth + 1)
              return (t:inner, remaining)
          | t == ")" =
              if depth == 0
                then Just ([], t:ts)
                else do
                  (inner, remaining) <- findMatchingParen ts (depth - 1)
                  return (t:inner, remaining)
          | otherwise = do
              (inner, remaining) <- findMatchingParen ts depth
              return (t:inner, remaining)

    reservedTypes :: [Text.Text]
    reservedTypes = ["String", "Int", "Bool", "Float", "Task", "Maybe", "List", "Result", "->", "(", ")"]

-- Flatten function type to see parameter count
flattenFunctionType :: FFIType -> ([FFIType], FFIType)
flattenFunctionType ffiType = case ffiType of
  FFIFunctionType params returnType ->
    let (nestedParams, finalReturn) = flattenFunctionType returnType
    in (params ++ nestedParams, finalReturn)
  otherType -> ([], otherType)

main :: IO ()
main = do
  let testTypes = [
        "UserActivated -> Initialized AudioContext -> Float -> Float -> String",
        "String -> String -> String -> String",
        "UserActivated -> Initialized AudioContext -> Float -> Float -> Task CapabilityError ()"
        ]

  mapM_ testType testTypes
  where
    testType typeStr = do
      putStrLn $ "=== Testing: " ++ Text.unpack typeStr ++ " ==="
      putStrLn ""

      let tokens = tokenizeCanopyType typeStr
      putStrLn "Tokens:"
      print tokens
      putStrLn ""

      case parseCanopyTypeAnnotation typeStr of
        Nothing -> putStrLn "Parse FAILED"
        Just ffiType -> do
          putStrLn "Parsed FFI Type:"
          print ffiType
          putStrLn ""

          let (params, returnType) = flattenFunctionType ffiType
          putStrLn $ "Parameter count: " ++ show (length params)
          putStrLn $ "Parameters: " ++ show params
          putStrLn $ "Return type: " ++ show returnType
      putStrLn ""