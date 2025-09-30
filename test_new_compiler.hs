#!/usr/bin/env stack
-- stack script --resolver lts-22.7

{-# LANGUAGE OverloadedStrings #-}

-- | Test script for the new query-based compiler.
--
-- This script validates that the new compiler can successfully compile
-- a simple module through all phases.

import qualified Canopy.Package as Pkg
import qualified Data.Map as Map
import qualified New.Compiler.Driver as Driver
import qualified Parse.Module as Parse
import System.Environment (setEnv)
import System.Exit (exitFailure, exitSuccess)

main :: IO ()
main = do
  -- Enable debug logging
  setEnv "CANOPY_DEBUG" "1"

  putStrLn "Testing new query-based compiler..."
  putStrLn ""

  -- Test path
  let testFile = "examples/audio-ffi/src/TestSimple.can"
  let pkg = Pkg.core  -- Using core package for test
  let ifaces = Map.empty  -- No dependencies for simple test

  putStrLn ("Compiling: " ++ testFile)
  putStrLn ""

  -- Compile the module
  result <- Driver.compileModule pkg ifaces testFile Parse.Package

  case result of
    Left err -> do
      putStrLn "COMPILATION FAILED:"
      print err
      exitFailure
    Right compileResult -> do
      putStrLn ""
      putStrLn "COMPILATION SUCCESSFUL!"
      putStrLn ""
      putStrLn "Module compiled successfully through all phases:"
      putStrLn "  ✓ Parse"
      putStrLn "  ✓ Canonicalize"
      putStrLn "  ✓ Type Check"
      putStrLn ""
      putStrLn ("Module: " ++ show (Driver.compileResultModule compileResult))
      putStrLn ""
      putStrLn ("Type bindings: " ++ show (Map.size (Driver.compileResultTypes compileResult)))
      exitSuccess
