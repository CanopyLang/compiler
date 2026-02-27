{-# LANGUAGE OverloadedStrings #-}
module NameReversalTest where

import qualified Canopy.Data.Name as Name
import qualified Data.ByteString as BS
import Test.HUnit

testStringBytes :: Test
testStringBytes = TestCase $ do
  let name = Name.fromChars "String"
  let bytes = BS.unpack (Name.toByteString name)
  -- Expected: [83,116,114,105,110,103] for "String"
  putStrLn $ "String bytes: " ++ show bytes
  assertEqual "String bytes should not be reversed"
    [83,116,114,105,110,103] bytes

testBoolBytes :: Test
testBoolBytes = TestCase $ do
  let name = Name.fromChars "Bool"
  let bytes = BS.unpack (Name.toByteString name)
  -- Expected: [66,111,111,108] for "Bool"
  putStrLn $ "Bool bytes: " ++ show bytes
  assertEqual "Bool bytes should not be reversed"
    [66,111,111,108] bytes

testIntBytes :: Test
testIntBytes = TestCase $ do
  let name = Name.fromChars "Int"
  let bytes = BS.unpack (Name.toByteString name)
  -- Expected: [73,110,116] for "Int"
  putStrLn $ "Int bytes: " ++ show bytes
  assertEqual "Int bytes should not be reversed"
    [73,110,116] bytes

tests :: Test
tests = TestList [testStringBytes, testBoolBytes, testIntBytes]
