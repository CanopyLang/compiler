#!/usr/bin/env stack
{- stack script
   --resolver lts-22.28
   --package text
-}

{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text
import Data.Text (Text)

-- Test the unit parameter stripping logic directly
stripUnitParams :: [Text] -> [Text]
stripUnitParams tokens =
  case findFunctionArrow tokens of
    Nothing -> tokens
    Just (paramTokens, restTokens) ->
      if paramTokens == ["(", ")"] || paramTokens == ["()"]
        then restTokens  -- Skip the unit parameter, return just the return type
        else tokens
  where
    findFunctionArrow :: [Text] -> Maybe ([Text], [Text])
    findFunctionArrow ts = go [] (0 :: Int) ts
      where
        go _ _ [] = Nothing
        go acc parenCount (t:rest)
          | t == "(" = go (acc ++ [t]) (parenCount + 1) rest
          | t == ")" = go (acc ++ [t]) (parenCount - 1) rest
          | t == "->" && parenCount == 0 = Just (acc, rest)
          | otherwise = go (acc ++ [t]) parenCount rest

main :: IO ()
main = do
  putStrLn "=== Testing Unit Parameter Stripping ==="

  let testCases =
        [ ["(", ")", "->", "Capability.UserActivated"]
        , ["String", "->", "Bool"]
        , ["Capability.UserActivated"]
        , ["(", ")", "->", "String", "->", "Bool"]
        ]

  mapM_ testStrip testCases
  where
    testStrip tokens = do
      putStrLn $ "\nInput: " ++ show tokens
      putStrLn $ "Output: " ++ show (stripUnitParams tokens)
