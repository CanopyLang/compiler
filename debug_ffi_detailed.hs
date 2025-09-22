#!/usr/bin/env stack
{- stack script
   --resolver lts-22.28
   --package text
-}

{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text
import Data.Text (Text)

-- Copy the parseBasicType related functions for testing
reservedTypes :: [Text]
reservedTypes = ["String", "Int", "Bool", "Float", "Task", "Maybe", "List", "Result", "->", "(", ")"]

data FFIType
  = FFIBasic Text
  | FFIOpaque Text
  | FFIFunction FFIType FFIType
  deriving (Show, Eq)

parseQualifiedType :: Text -> Maybe FFIType
parseQualifiedType qualifiedName
  | Text.isInfixOf "." qualifiedName && not (qualifiedName `elem` reservedTypes) =
      let unqualifiedName = Text.takeWhileEnd (/= '.') qualifiedName
      in Just (FFIOpaque unqualifiedName)
  | not (qualifiedName `elem` reservedTypes) =
      Just (FFIOpaque qualifiedName)
  | otherwise = Nothing

main :: IO ()
main = do
  putStrLn "=== Testing Qualified Name Parsing ==="

  let testCases =
        [ "Capability.UserActivated"
        , "UserActivated"
        , "Capability.Available"
        , "Available"
        , "String"
        , "Task"
        ]

  mapM_ testParse testCases
  where
    testParse name = do
      putStrLn $ "\nInput: " ++ Text.unpack name
      putStrLn $ "Result: " ++ show (parseQualifiedType name)
