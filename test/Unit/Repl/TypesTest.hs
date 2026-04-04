{-# LANGUAGE OverloadedStrings #-}

-- | Tests for REPL core types.
--
-- Verifies constructors, Line operations, and Output operations
-- for the REPL type system.
--
-- @since 0.19.2
module Unit.Repl.TypesTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.UTF8 as BS_UTF8
import Repl.Types
  ( CategorizedInput (..),
    Input (..),
    Lines (..),
    Output (..),
    Prefill (..),
    addLine,
    endsWithBlankLine,
    getFirstLine,
    isSingleLine,
    linesToByteString,
    outputToBuilder,
    toPrintName,
  )
import Test.Tasty
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  testGroup
    "Repl.Types"
    [ inputTests,
      linesTests,
      outputTests,
      categorizedInputTests
    ]

-- INPUT TYPE TESTS

inputTests :: TestTree
inputTests =
  testGroup
    "Input constructors"
    [ HUnit.testCase "TypeOf stores expression string" $
        showTypeOf HUnit.@?= "TypeOf \"List.map\"",
      HUnit.testCase "Browse Nothing for no argument" $
        showBrowseNone HUnit.@?= "Browse Nothing",
      HUnit.testCase "Browse (Just mod) for module argument" $
        showBrowseMod HUnit.@?= "Browse (Just \"String\")",
      HUnit.testCase "Skip show is Skip" $
        show Skip HUnit.@?= "Skip",
      HUnit.testCase "Exit show is Exit" $
        show Exit HUnit.@?= "Exit",
      HUnit.testCase "Reset show is Reset" $
        show Reset HUnit.@?= "Reset",
      HUnit.testCase "Port show is Port" $
        show Port HUnit.@?= "Port",
      HUnit.testCase "Help Nothing show" $
        show (Help Nothing) HUnit.@?= "Help Nothing"
    ]
  where
    showTypeOf = show (TypeOf "List.map")
    showBrowseNone = show (Browse Nothing)
    showBrowseMod = show (Browse (Just "String"))

-- LINES TESTS

linesTests :: TestTree
linesTests =
  testGroup
    "Lines Operations"
    [ addLineTests,
      singleLineTests,
      endsWithBlankTests,
      getFirstLineTests,
      linesToByteStringTests
    ]

addLineTests :: TestTree
addLineTests =
  testGroup
    "addLine"
    [ HUnit.testCase "adds line to single-line input" $
        addLine "second" (Lines "first" []) HUnit.@?= Lines "second" ["first"],
      HUnit.testCase "adds line to multi-line input" $
        addLine "third" (Lines "second" ["first"]) HUnit.@?= Lines "third" ["second", "first"]
    ]

singleLineTests :: TestTree
singleLineTests =
  testGroup
    "isSingleLine"
    [ HUnit.testCase "true for single line" $
        isSingleLine (Lines "hello" []) HUnit.@?= True,
      HUnit.testCase "false for multiple lines" $
        isSingleLine (Lines "second" ["first"]) HUnit.@?= False
    ]

endsWithBlankTests :: TestTree
endsWithBlankTests =
  testGroup
    "endsWithBlankLine"
    [ HUnit.testCase "true for blank current line" $
        endsWithBlankLine (Lines "" ["first"]) HUnit.@?= True,
      HUnit.testCase "true for whitespace current line" $
        endsWithBlankLine (Lines "   " ["first"]) HUnit.@?= True,
      HUnit.testCase "false for non-blank current line" $
        endsWithBlankLine (Lines "hello" ["first"]) HUnit.@?= False
    ]

getFirstLineTests :: TestTree
getFirstLineTests =
  testGroup
    "getFirstLine"
    [ HUnit.testCase "returns only line for single-line input" $
        getFirstLine (Lines "hello" []) HUnit.@?= "hello",
      HUnit.testCase "returns first entered line for multi-line input" $
        getFirstLine (Lines "third" ["second", "first"]) HUnit.@?= "first"
    ]

linesToByteStringTests :: TestTree
linesToByteStringTests =
  testGroup
    "linesToByteString"
    [ HUnit.testCase "single line produces correct ByteString" $
        linesToByteString (Lines "hello" []) HUnit.@?= BS_UTF8.fromString "hello\n",
      HUnit.testCase "multi-line joins with newlines" $
        linesToByteString (Lines "c" ["b", "a"]) HUnit.@?= BS_UTF8.fromString "a\nb\nc\n"
    ]

-- OUTPUT TESTS

outputTests :: TestTree
outputTests =
  testGroup
    "Output Operations"
    [ toPrintNameTests,
      outputToBuilderTests
    ]

toPrintNameTests :: TestTree
toPrintNameTests =
  testGroup
    "toPrintName"
    [ HUnit.testCase "OutputNothing returns Nothing" $
        toPrintName OutputNothing HUnit.@?= Nothing,
      HUnit.testCase "OutputDecl returns Just name" $
        toPrintName (OutputDecl fooName) HUnit.@?= Just fooName,
      HUnit.testCase "OutputExpr returns Just replValueToPrint" $
        toPrintName (OutputExpr "42") HUnit.@?= Just Name.replValueToPrint
    ]
  where
    fooName = Name.fromChars "foo"

outputToBuilderTests :: TestTree
outputToBuilderTests =
  testGroup
    "outputToBuilder"
    [ HUnit.testCase "OutputNothing produces exact unit binding" $
        builderToBS (outputToBuilder OutputNothing)
          HUnit.@?= BS_UTF8.fromString "repl_input_value_ = ()\n",
      HUnit.testCase "OutputDecl produces exact unit binding" $
        builderToBS (outputToBuilder (OutputDecl (Name.fromChars "x")))
          HUnit.@?= BS_UTF8.fromString "repl_input_value_ = ()\n",
      HUnit.testCase "OutputExpr produces exact multiline binding" $
        builderToBS (outputToBuilder (OutputExpr "42 + 1"))
          HUnit.@?= BS_UTF8.fromString "repl_input_value_ =\n  42 + 1\n"
    ]

-- CATEGORIZED INPUT TESTS

categorizedInputTests :: TestTree
categorizedInputTests =
  testGroup
    "CategorizedInput"
    [ HUnit.testCase "Done Skip show" $
        show (Done Skip) HUnit.@?= "Done Skip",
      HUnit.testCase "Continue Indent show" $
        show (Continue Indent) HUnit.@?= "Continue Indent"
    ]

-- HELPERS

-- | Convert a Builder to strict ByteString for testing.
builderToBS :: BB.Builder -> BSC.ByteString
builderToBS = LBS.toStrict . BB.toLazyByteString
