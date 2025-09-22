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

main :: IO ()
main = do
  putStrLn "=== Tokenizing FFI Type Signatures ==="

  let signatures =
        [ "() -> Capability.UserActivated"
        , "String -> Bool"
        , "(() -> Capability.Available ()) -> Capability.Available ()"
        , "String -> (() -> Task Capability.CapabilityError a) -> (a -> Capability.Initialized a) -> Task Capability.CapabilityError (Capability.Initialized a)"
        ]

  mapM_ testTokenize signatures
  where
    testTokenize sig = do
      putStrLn $ "\nSignature: " ++ Text.unpack sig
      putStrLn $ "Tokens: " ++ show (tokenizeType sig)
