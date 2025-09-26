#!/usr/bin/env stack
{- stack script --resolver lts-22.27 -}

-- | Test FFI parsing functionality to debug AudioFFI compilation issues
module Main where

import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import qualified Foreign.FFI as FFI

main :: IO ()
main = do
  putStrLn "=== Testing FFI Parsing for Audio FFI Example ==="

  -- Test parsing the audio.js file
  let jsFile = "examples/audio-ffi/external/audio.js"
  putStrLn $ "Testing parsing of: " ++ jsFile

  result <- FFI.parseJSDocFromFile jsFile
  case result of
    Left err -> do
      putStrLn $ "ERROR: " ++ show err
    Right functions -> do
      putStrLn $ "SUCCESS: Found " ++ show (length functions) ++ " FFI functions:"
      mapM_ printFunction functions

      -- Test type parsing for each function
      putStrLn "\n=== Testing Type Parsing ==="
      mapM_ testTypeParsing functions

printFunction :: FFI.JSDocFunction -> IO ()
printFunction func = do
  putStrLn $ "  - " ++ Text.unpack (FFI.jsDocFuncName func)
  putStrLn $ "    Type: " ++ show (FFI.jsDocFuncType func)
  putStrLn $ "    File: " ++ FFI.jsDocFuncFile func

testTypeParsing :: FFI.JSDocFunction -> IO ()
testTypeParsing func = do
  let funcName = FFI.jsDocFuncName func
      ffiType = FFI.jsDocFuncType func
  putStrLn $ "Function: " ++ Text.unpack funcName
  case FFI.ffiTypeToCanopyType ffiType of
    Left err -> putStrLn $ "  Type conversion FAILED: " ++ show err
    Right canopyType -> putStrLn $ "  Canopy type: " ++ Text.unpack canopyType
  putStrLn ""