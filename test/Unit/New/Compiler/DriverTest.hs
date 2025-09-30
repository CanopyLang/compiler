{-# OPTIONS_GHC -Wall #-}

-- | Tests for the new query-based compiler driver.
--
-- @since 0.19.1
module Unit.New.Compiler.DriverTest (tests) where

import qualified Canopy.Package as Pkg
import qualified Data.Map as Map
import qualified New.Compiler.Driver as Driver
import qualified Parse.Module as Parse
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase)

tests :: TestTree
tests =
  testGroup
    "New.Compiler.Driver"
    [ testGroup
        "compileModule"
        [ testCase "compiles simple module" testSimpleModule
        ]
    ]

-- | Test compiling a simple module.
testSimpleModule :: IO ()
testSimpleModule = do
  let testFile = "examples/audio-ffi/src/TestSimple.can"
  let pkg = Pkg.core
  let ifaces = Map.empty
  let projectType = Parse.Package pkg

  result <- Driver.compileModule pkg ifaces testFile projectType

  case result of
    Left err ->
      assertBool
        ("Expected successful compilation, got error: " ++ show err)
        False
    Right _compileResult ->
      assertBool "Module compiled successfully" True
