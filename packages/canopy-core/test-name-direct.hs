{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Name as Name

main :: IO ()
main = do
  let input = "MyType"
  let name = Name.fromChars input
  let output = Name.toChars name
  putStrLn (" Input:  " ++ show input)
  putStrLn ("Output: " ++ show output)
  if input == output
    then putStrLn "✅ PASS: No reversal"
    else putStrLn ("❌ FAIL: Reversed! " ++ show input ++ " -> " ++ show output)

  -- Test more names
  testName "String"
  testName "Task"
  testName "MyError"
  testName "AudioContext"

testName :: String -> IO ()
testName input = do
  let name = Name.fromChars input
  let output = Name.toChars name
  if input == output
    then putStrLn ("✅ " ++ input ++ " -> " ++ output)
    else putStrLn ("❌ " ++ input ++ " -> " ++ output ++ " (REVERSED!)")
