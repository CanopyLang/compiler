#!/usr/bin/env stack
{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Name as Name
import qualified Data.Char as Char

main :: IO ()
main = do
  putStrLn "Testing Name.fromChars for byte reversal..."
  putStrLn ""

  -- Test "String"
  let nameString = Name.fromChars "String"
  let charsString = Name.toChars nameString
  let bytesString = map Char.ord charsString
  putStrLn $ "Input:     " ++ show "String"
  putStrLn $ "Roundtrip: " ++ show charsString
  putStrLn $ "Bytes:     " ++ show bytesString
  putStrLn $ "Expected:  [83,116,114,105,110,103]"
  putStrLn $ "Match: " ++ show (bytesString == [83,116,114,105,110,103])
  putStrLn ""

  -- Test "Bool"
  let nameBool = Name.fromChars "Bool"
  let charsBool = Name.toChars nameBool
  let bytesBool = map Char.ord charsBool
  putStrLn $ "Input:     " ++ show "Bool"
  putStrLn $ "Roundtrip: " ++ show charsBool
  putStrLn $ "Bytes:     " ++ show bytesBool
  putStrLn $ "Expected:  [66,111,111,108]"
  putStrLn $ "Match: " ++ show (bytesBool == [66,111,111,108])
  putStrLn ""

  -- Test "Int"
  let nameInt = Name.fromChars "Int"
  let charsInt = Name.toChars nameInt
  let bytesInt = map Char.ord charsInt
  putStrLn $ "Input:     " ++ show "Int"
  putStrLn $ "Roundtrip: " ++ show charsInt
  putStrLn $ "Bytes:     " ++ show bytesInt
  putStrLn $ "Expected:  [73,110,116]"
  putStrLn $ "Match: " ++ show (bytesInt == [73,110,116])
