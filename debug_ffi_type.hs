#!/usr/bin/env stack
{- stack
  script
  --resolver lts-22.30
  --package text
-}

{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text

-- Minimal test to debug FFI type parsing
tokenizeCanopyType :: Text.Text -> [Text.Text]
tokenizeCanopyType typeText = filter (not . Text.null) (go [] "" typeText)
  where
    go :: [Text.Text] -> Text.Text -> Text.Text -> [Text.Text]
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

main :: IO ()
main = do
  let testType = "UserActivated -> Initialized AudioContext -> Float -> Float -> Task CapabilityError ()"
  let tokens = tokenizeCanopyType testType

  putStrLn "Type annotation:"
  putStrLn (Text.unpack testType)
  putStrLn ""
  putStrLn "Tokenized:"
  mapM_ (putStrLn . Text.unpack) tokens