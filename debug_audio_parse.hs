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

stripOuterParens :: [Text] -> [Text]
stripOuterParens ts = case ts of
  "(" : rest -> case matchingParen rest 0 of
    Just (inner, []) -> inner  -- Outer parens enclose everything
    _ -> ts  -- Keep original if not properly enclosed
  _ -> ts

matchingParen :: [Text] -> Int -> Maybe ([Text], [Text])
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

main :: IO ()
main = do
  let testTypes =
        [ "() -> Task CapabilityError UserActivated"
        , "UserActivated -> Initialized AudioContext -> Float -> Float -> Task CapabilityError ()"
        ]

  mapM_ testType testTypes

testType :: Text -> IO ()
testType testTypeStr = do
  let testType = testTypeStr
  putStrLn $ "Input: " ++ show testType

  let tokens = tokenizeType testType
  putStrLn $ "Tokens: " ++ show tokens

  let stripped = stripOuterParens tokens
  putStrLn $ "After stripOuterParens: " ++ show stripped

  case findFunctionArrow stripped of
    Nothing -> putStrLn "No function arrow found"
    Just (paramTokens, restTokens) -> do
      putStrLn $ "Param tokens: " ++ show paramTokens
      putStrLn $ "Rest tokens: " ++ show restTokens
      putStrLn $ "Is unit param? " ++ show (paramTokens == ["(", ")"] || paramTokens == ["()"])
  putStrLn ""

findFunctionArrow :: [Text] -> Maybe ([Text], [Text])
findFunctionArrow ts = go [] (0 :: Int) ts
  where
    go _ _ [] = Nothing
    go acc parenCount (t:rest)
      | t == "(" = go (acc ++ [t]) (parenCount + 1) rest
      | t == ")" = go (acc ++ [t]) (parenCount - 1) rest
      | t == "->" && parenCount == 0 = Just (acc, rest)
      | otherwise = go (acc ++ [t]) parenCount rest