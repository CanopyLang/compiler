#!/usr/bin/env stack
{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Name as Name
import qualified Data.ByteString as BS

main :: IO ()
main = do
  putStrLn "Testing Name.fromChars for byte reversal..."

  -- Test "String"
  let nameString = Name.fromChars "String"
  let bytesString = BS.unpack (Name.toByteString nameString)
  putStrLn $ "String input: " ++ show "String"
  putStrLn $ "String bytes: " ++ show bytesString
  putStrLn $ "Expected:     [83,116,114,105,110,103]"
  putStrLn $ "Match: " ++ show (bytesString == [83,116,114,105,110,103])
  putStrLn ""

  -- Test "Bool"
  let nameBool = Name.fromChars "Bool"
  let bytesBool = BS.unpack (Name.toByteString nameBool)
  putStrLn $ "Bool input: " ++ show "Bool"
  putStrLn $ "Bool bytes: " ++ show bytesBool
  putStrLn $ "Expected:   [66,111,111,108]"
  putStrLn $ "Match: " ++ show (bytesBool == [66,111,111,108])
  putStrLn ""

  -- Test "Int"
  let nameInt = Name.fromChars "Int"
  let bytesInt = BS.unpack (Name.toByteString nameInt)
  putStrLn $ "Int input: " ++ show "Int"
  putStrLn $ "Int bytes: " ++ show bytesInt
  putStrLn $ "Expected:  [73,110,116]"
  putStrLn $ "Match: " ++ show (bytesInt == [73,110,116])
  putStrLn ""

  -- Test roundtrip
  let roundtripString = Name.toChars nameString
  let roundtripBool = Name.toChars nameBool
  let roundtripInt = Name.toChars nameInt

  putStrLn "Roundtrip tests:"
  putStrLn $ "String roundtrip: " ++ show roundtripString ++ " (expected: String)"
  putStrLn $ "Bool roundtrip: " ++ show roundtripBool ++ " (expected: Bool)"
  putStrLn $ "Int roundtrip: " ++ show roundtripInt ++ " (expected: Int)"
