#!/usr/bin/env stack
{- stack script --resolver lts-22.28 --package base --package text --package containers -}

-- Test parsing of generic FFI type annotations with type variables

{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text
import Data.Char (isLower, isUpper)

-- Simplified tokenizer
tokenizeCanopyType :: Text.Text -> [String]
tokenizeCanopyType input =
  let str = Text.unpack (Text.strip input)
  in tokenize str []
  where
    tokenize [] acc = reverse acc
    tokenize (' ' : rest) acc = tokenize rest acc
    tokenize ('(' : rest) acc = tokenize rest ("(" : acc)
    tokenize (')' : rest) acc = tokenize rest (")" : acc)
    tokenize ('-' : '>' : rest) acc = tokenize rest ("->" : acc)
    tokenize str acc =
      let (word, rest) = span (\c -> c /= ' ' && c /= '(' && c /= ')' && c /= '-') str
      in tokenize rest (word : acc)

-- Check if a string is a type variable (single lowercase letter)
isTypeVariable :: String -> Bool
isTypeVariable [c] = isLower c
isTypeVariable _ = False

-- Test cases
testCases :: [Text.Text]
testCases =
  [ "String -> a -> Task CapabilityError a"
  , "a"
  , "Task"
  , "a -> b"
  , "String -> (() -> Task CapabilityError a) -> (a -> Initialized a) -> Task CapabilityError (Initialized a)"
  ]

main :: IO ()
main = do
  putStrLn "Testing type variable detection in FFI annotations:\n"
  mapM_ testCase testCases
  where
    testCase typeStr = do
      let tokens = tokenizeCanopyType typeStr
      putStrLn $ "Type: " ++ Text.unpack typeStr
      putStrLn $ "Tokens: " ++ show tokens
      putStrLn "Type variable detection:"
      mapM_ (\t -> putStrLn $ "  " ++ t ++ " -> " ++ show (isTypeVariable t)) tokens
      putStrLn ""
