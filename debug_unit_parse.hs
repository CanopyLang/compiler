#!/usr/bin/env stack
-- stack script --resolver lts-18.18 --package text

{-# LANGUAGE OverloadedStrings #-}
import Data.Text (Text)
import qualified Data.Text as Text

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
  let testTypes =
        [ "()"
        , "() -> String"
        , "String"
        ]

  mapM_ (\typeText -> do
    putStrLn $ "Input: " ++ show typeText
    putStrLn $ "Tokens: " ++ show (tokenizeType typeText)
    putStrLn ""
    ) testTypes