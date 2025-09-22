#!/usr/bin/env stack
{- stack script
   --resolver lts-22.28
   --package text
-}

{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text
import Data.Text (Text)

-- Copy the tokenizeType function
tokenizeType :: Text -> [Text]
tokenizeType = go [] ""
  where
    go acc current text
      | Text.null text =
          if Text.null current then acc else acc ++ [current]
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

-- Strip unit parameters
stripUnitParams :: [Text] -> [Text]
stripUnitParams tokens =
  case findFunctionArrow tokens of
    Nothing -> tokens
    Just (paramTokens, restTokens) ->
      if paramTokens == ["(", ")"] || paramTokens == ["()"]
        then restTokens  -- Skip the unit parameter
        else tokens
  where
    findFunctionArrow ts = go [] (0 :: Int) ts
      where
        go _ _ [] = Nothing
        go acc parenCount (t:rest)
          | t == "(" = go (acc ++ [t]) (parenCount + 1) rest
          | t == ")" = go (acc ++ [t]) (parenCount - 1) rest
          | t == "->" && parenCount == 0 = Just (acc, rest)
          | otherwise = go (acc ++ [t]) parenCount rest

-- Strip qualified names
stripQualifiedNames :: [Text] -> [Text]
stripQualifiedNames = map stripQualified
  where
    stripQualified typeName
      | Text.isInfixOf "." typeName = Text.takeWhileEnd (/= '.') typeName
      | otherwise = typeName

-- Full processing pipeline
processFFISignature :: Text -> [Text]
processFFISignature signature =
  signature
    |> tokenizeType
    |> stripUnitParams
    |> stripQualifiedNames
  where
    (|>) = flip ($)

main :: IO ()
main = do
  putStrLn "=== Testing Full FFI Signature Processing ==="

  let signatures =
        [ "() -> Capability.UserActivated"
        , "Capability.UserActivated"
        , "String -> Capability.Available"
        , "(() -> Capability.Available ()) -> Capability.Available ()"
        ]

  mapM_ testProcess signatures
  where
    testProcess sig = do
      putStrLn $ "\nSignature: " ++ Text.unpack sig
      putStrLn $ "Tokens: " ++ show (tokenizeType sig)
      putStrLn $ "After unit strip: " ++ show (stripUnitParams (tokenizeType sig))
      putStrLn $ "Final result: " ++ show (processFFISignature sig)
