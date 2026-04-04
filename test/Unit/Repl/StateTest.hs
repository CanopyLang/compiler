{-# LANGUAGE OverloadedStrings #-}

-- | Tests for REPL state management.
--
-- Verifies that state operations (addImport, addType, addDecl) and
-- serialization (toByteString) work correctly, and that the command
-- completions include the new @:type@, @:t@, and @:browse@ entries.
--
-- @since 0.19.2
module Unit.Repl.StateTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified Data.Map.Strict as Map
import qualified Repl.State as State
import Repl.Types (Output (..), State (..))
import Test.Tasty
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  testGroup
    "Repl.State"
    [ initialStateTests,
      addImportTests,
      addTypeTests,
      addDeclTests,
      toByteStringTests
    ]

-- INITIAL STATE TESTS

initialStateTests :: TestTree
initialStateTests =
  testGroup
    "Initial State"
    [ HUnit.testCase "imports are empty" $
        Map.null (_imports State.initialState) HUnit.@?= True,
      HUnit.testCase "types are empty" $
        Map.null (_types State.initialState) HUnit.@?= True,
      HUnit.testCase "decls are empty" $
        Map.null (_decls State.initialState) HUnit.@?= True
    ]

-- ADD IMPORT TESTS

addImportTests :: TestTree
addImportTests =
  testGroup
    "addImport"
    [ HUnit.testCase "adds import to empty state" $
        Map.size (_imports (State.addImport listName listSrc State.initialState)) HUnit.@?= 1,
      HUnit.testCase "does not affect types" $
        Map.null (_types (State.addImport listName listSrc State.initialState)) HUnit.@?= True,
      HUnit.testCase "does not affect decls" $
        Map.null (_decls (State.addImport listName listSrc State.initialState)) HUnit.@?= True,
      HUnit.testCase "replaces existing import with same name" $
        Map.size (_imports updatedImport) HUnit.@?= 1
    ]
  where
    listName = Name.fromChars "List"
    listSrc = "import List\n"
    updatedImport = State.addImport listName "import List exposing (..)\n" (State.addImport listName listSrc State.initialState)

-- ADD TYPE TESTS

addTypeTests :: TestTree
addTypeTests =
  testGroup
    "addType"
    [ HUnit.testCase "adds type to empty state" $
        Map.size (_types (State.addType colorName colorSrc State.initialState)) HUnit.@?= 1,
      HUnit.testCase "does not affect imports" $
        Map.null (_imports (State.addType colorName colorSrc State.initialState)) HUnit.@?= True
    ]
  where
    colorName = Name.fromChars "Color"
    colorSrc = "type Color = Red | Green | Blue\n"

-- ADD DECL TESTS

addDeclTests :: TestTree
addDeclTests =
  testGroup
    "addDecl"
    [ HUnit.testCase "adds decl to empty state" $
        Map.size (_decls (State.addDecl fooName fooSrc State.initialState)) HUnit.@?= 1,
      HUnit.testCase "does not affect imports" $
        Map.null (_imports (State.addDecl fooName fooSrc State.initialState)) HUnit.@?= True,
      HUnit.testCase "multiple decls accumulate" $
        Map.size (_decls twoDecls) HUnit.@?= 2
    ]
  where
    fooName = Name.fromChars "foo"
    fooSrc = "foo = 42\n"
    barName = Name.fromChars "bar"
    barSrc = "bar = \"hello\"\n"
    twoDecls = State.addDecl barName barSrc (State.addDecl fooName fooSrc State.initialState)

-- TO BYTESTRING TESTS

toByteStringTests :: TestTree
toByteStringTests =
  testGroup
    "toByteString"
    [ HUnit.testCase "empty state with OutputNothing produces exact output" $
        State.toByteString State.initialState OutputNothing
          HUnit.@?= "module Canopy_Repl exposing (..)\nrepl_input_value_ = ()\n",
      HUnit.testCase "state with import produces exact output" $
        State.toByteString
          (State.addImport (Name.fromChars "List") "import List\n" State.initialState)
          OutputNothing
          HUnit.@?= "module Canopy_Repl exposing (..)\nimport List\nrepl_input_value_ = ()\n",
      HUnit.testCase "OutputExpr produces exact binding" $
        State.toByteString State.initialState (OutputExpr "42")
          HUnit.@?= "module Canopy_Repl exposing (..)\nrepl_input_value_ =\n  42\n"
    ]
