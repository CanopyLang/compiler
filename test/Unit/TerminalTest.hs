{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Terminal module.
--
-- Tests the Terminal framework's public API including argument builders,
-- flag builders, parser creation, and type constructors. Validates that
-- all re-exported functions work correctly and type constructors have
-- proper behavior.
--
-- @since 0.19.1
module Unit.TerminalTest (tests) where

import qualified Data.List as List
import qualified System.Directory as Directory
import qualified Terminal
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty, (==>))
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

tests :: TestTree
tests =
  testGroup
    "Terminal Tests"
    [ testParserCreation,
      testArgumentBuilders,
      testFlagBuilders,
      testTypeConstructors,
      testIntegrationProperties,
      testErrorConditions
    ]

-- | Test parser creation functions
testParserCreation :: TestTree
testParserCreation =
  testGroup
    "Parser Creation Tests"
    [ testCase "stringParser creates valid parser" $ do
        let parser = Terminal.stringParser "input" "description"
            Terminal.Parser singular plural parseFunc _ _ = parser
        singular @?= "input"
        plural @?= "inputs"
        parseFunc "test" @?= Just "test"
        parseFunc "" @?= Just "",
      testCase "intParser validates bounds correctly" $ do
        let parser = Terminal.intParser 1 10
            Terminal.Parser singular plural parseFunc _ _ = parser
        singular @?= "number"
        plural @?= "numbers"
        parseFunc "5" @?= Just 5
        parseFunc "1" @?= Just 1
        parseFunc "10" @?= Just 10
        parseFunc "0" @?= Nothing
        parseFunc "11" @?= Nothing
        parseFunc "abc" @?= Nothing,
      testCase "boolParser handles various representations" $ do
        let parser = Terminal.boolParser
            Terminal.Parser _ _ parseFunc _ _ = parser
        parseFunc "true" @?= Just True
        parseFunc "false" @?= Just False
        parseFunc "yes" @?= Just True
        parseFunc "no" @?= Just False
        parseFunc "1" @?= Just True
        parseFunc "0" @?= Just False
        parseFunc "maybe" @?= Nothing,
      testCase "floatParser handles numeric input" $ do
        let parser = Terminal.floatParser
            Terminal.Parser _ _ parseFunc _ _ = parser
        parseFunc "1.5" @?= Just 1.5
        parseFunc "0.5" @?= Just 0.5
        parseFunc "-3.14" @?= Just (-3.14)
        parseFunc "abc" @?= Nothing,
      testCase "fileParser accepts all files with empty extensions" $ do
        let parser = Terminal.fileParser []
            Terminal.Parser singular plural parseFunc _ _ = parser
        singular @?= "file"
        plural @?= "files"
        parseFunc "test.txt" @?= Just "test.txt"
        parseFunc "script.hs" @?= Just "script.hs"
        parseFunc "document" @?= Just "document"
    ]

-- | Test argument builder functions
testArgumentBuilders :: TestTree
testArgumentBuilders =
  testGroup
    "Argument Builders Tests"
    [ testCase "noArgs creates empty argument specification" $ do
        let args = Terminal.noArgs
        case args of
          Terminal.Args [Terminal.Exactly (Terminal.Done ())] -> pure () -- noArgs creates exactly Done ()
          _ -> assertFailure "noArgs should create exactly Done ()",
      testCase "required creates single required argument" $ do
        let parser = Terminal.stringParser "name" "description"
            args = Terminal.required parser
        case args of
          Terminal.Args [Terminal.Exactly (Terminal.Required (Terminal.Done _) _)] -> pure () -- required creates Required pattern
          _ -> assertFailure "required should create Required pattern",
      testCase "optional creates optional argument" $ do
        let parser = Terminal.stringParser "name" "description"
            args = Terminal.optional parser
        case args of
          Terminal.Args [Terminal.Optional (Terminal.Done _) _] -> pure () -- optional creates Optional pattern
          _ -> assertFailure "optional should create Optional pattern",
      testCase "zeroOrMore creates multiple argument pattern" $ do
        let parser = Terminal.stringParser "name" "description"
            args = Terminal.zeroOrMore parser
        case args of
          Terminal.Args [Terminal.Multiple (Terminal.Done _) _] -> pure () -- zeroOrMore creates Multiple pattern
          _ -> assertFailure "zeroOrMore should create Multiple pattern",
      testCase "oneOf combines multiple argument patterns" $ do
        let parser1 = Terminal.stringParser "name1" "desc1"
            parser2 = Terminal.stringParser "name2" "desc2"
            args1 = Terminal.required parser1
            args2 = Terminal.required parser2
            combined = Terminal.oneOf [args1, args2]
        case combined of
          Terminal.Args alternatives -> length alternatives @?= 2,
      testCase "require0 creates args with fixed value" $ do
        let args = Terminal.require0 "fixed"
        case args of
          Terminal.Args [Terminal.Exactly (Terminal.Done "fixed")] -> pure () -- require0 creates Done with value
          _ -> assertFailure "require0 should create Done with value",
      testCase "require1 creates single argument with function" $ do
        let parser = Terminal.stringParser "input" "description"
            args = Terminal.require1 id parser
        case args of
          Terminal.Args [Terminal.Exactly (Terminal.Required (Terminal.Done _) _)] -> pure () -- require1 creates Required pattern
          _ -> assertFailure "require1 should create Required pattern",
      testCase "require2 creates two-argument pattern" $ do
        let parser1 = Terminal.stringParser "first" "description"
            parser2 = Terminal.stringParser "second" "description"
            args = Terminal.require2 (,) parser1 parser2
        case args of
          Terminal.Args [Terminal.Exactly (Terminal.Required (Terminal.Required (Terminal.Done _) _) _)] -> pure () -- require2 creates nested Required pattern
          _ -> assertFailure "require2 should create nested Required pattern"
    ]

-- | Test flag builder functions
testFlagBuilders :: TestTree
testFlagBuilders =
  testGroup
    "Flag Builders Tests"
    [ testCase "noFlags creates empty flag specification" $ do
        let flags = Terminal.noFlags
        case flags of
          Terminal.FDone () -> pure () -- noFlags creates FDone ()
          _ -> assertFailure "noFlags should create FDone ()",
      testCase "flags creates flag specification with value" $ do
        let flags = Terminal.flags "test"
        case flags of
          Terminal.FDone "test" -> pure () -- flags creates FDone with value
          _ -> assertFailure "flags should create FDone with value",
      testCase "flag creates value flag" $ do
        let parser = Terminal.stringParser "value" "description"
            flagDef = Terminal.flag "output" parser "output directory"
        case flagDef of
          Terminal.Flag "output" _ "output directory" -> pure () -- flag creates Flag with correct parameters
          _ -> assertFailure "flag should create Flag with correct parameters",
      testCase "onOff creates boolean flag" $ do
        let flagDef = Terminal.onOff "verbose" "enable verbose output"
        case flagDef of
          Terminal.OnOff "verbose" "enable verbose output" -> pure () -- onOff creates OnOff flag
          _ -> assertFailure "onOff should create OnOff flag",
      testCase "onOffFlag creates boolean flag (alias)" $ do
        let flagDef = Terminal.onOffFlag "debug" "enable debug mode"
        case flagDef of
          Terminal.OnOff "debug" "enable debug mode" -> pure () -- onOffFlag creates OnOff flag
          _ -> assertFailure "onOffFlag should create OnOff flag"
    ]

-- | Test type constructors and data types
testTypeConstructors :: TestTree
testTypeConstructors =
  testGroup
    "Type Constructor Tests"
    [ testCase "Summary Common contains description" $ do
        let summary = Terminal.Common "test description"
        case summary of
          Terminal.Common desc -> desc @?= "test description"
          _ -> assertFailure "Common should contain description",
      testCase "Summary Uncommon has no description" $ do
        let summary = Terminal.Uncommon
        case summary of
          Terminal.Uncommon -> pure () -- Uncommon has no description
          _ -> assertFailure "Uncommon should have no description",
      testCase "Parser has all required fields" $ do
        let parser = Terminal.stringParser "test" "description"
            Terminal.Parser singular plural parseFunc suggestFunc exampleFunc = parser
        singular @?= "test"
        plural @?= "tests"
        parseFunc "input" @?= Just "input"
        -- Test that suggest and example functions exist and return IO
        suggestions <- suggestFunc "prefix"
        -- Test that suggest function exists and can be called without error
        pure () -- Function call succeeded
        examples <- exampleFunc "input"
        -- Test that example function exists and can be called without error
        pure (), -- Function call succeeded
      testCase "Flags FDone contains value" $ do
        let flags = Terminal.FDone 42
        case flags of
          Terminal.FDone 42 -> pure () -- FDone contains value
          _ -> assertFailure "FDone should contain value",
      testCase "Flag construction preserves parameters" $ do
        let parser = Terminal.stringParser "param" "description"
            flag = Terminal.Flag "name" parser "help text"
        case flag of
          Terminal.Flag "name" _ "help text" -> pure () -- Flag preserves name and help text
          _ -> assertFailure "Flag should preserve name and help text"
    ]

-- | Test integration properties and behavior
testIntegrationProperties :: TestTree
testIntegrationProperties =
  testGroup
    "Integration Properties"
    [ testProperty "stringParser roundtrip property" $ \input ->
        let parser = Terminal.stringParser "test" "description"
            Terminal.Parser _ _ parseFunc _ _ = parser
         in parseFunc input == Just input,
      testProperty "intParser respects bounds" $ \n ->
        let minVal = 1
            maxVal = 100
            parser = Terminal.intParser minVal maxVal
            Terminal.Parser _ _ parseFunc _ _ = parser
            result = parseFunc (show n)
         in case result of
              Just parsed -> parsed >= minVal && parsed <= maxVal
              Nothing -> n < minVal || n > maxVal,
      testProperty "noArgs always creates empty specification" $ \() ->
        let args = Terminal.noArgs
         in case args of
              Terminal.Args [Terminal.Exactly (Terminal.Done ())] -> True
              _ -> False,
      testProperty "flags preserves any value" $ \(value :: String) ->
        let flags = Terminal.flags value
         in case flags of
              Terminal.FDone actualValue -> actualValue == value
              _ -> False,
      testCase "file suggestions work for current directory" $ do
        let parser = Terminal.fileParser []
            Terminal.Parser _ _ _ suggestFunc _ = parser
        suggestions <- suggestFunc "."
        -- Should return some suggestions or empty list
        -- Test that suggest function exists and can be called without error
        pure () -- Function call succeeded
    ]

-- | Test error conditions and edge cases
testErrorConditions :: TestTree
testErrorConditions =
  testGroup
    "Error Conditions Tests"
    [ testCase "intParser rejects invalid input" $ do
        let parser = Terminal.intParser 1 10
            Terminal.Parser _ _ parseFunc _ _ = parser
        parseFunc "not-a-number" @?= Nothing
        parseFunc "" @?= Nothing
        parseFunc "1.5" @?= Nothing,
      testCase "intParser rejects out-of-bounds values" $ do
        let parser = Terminal.intParser 5 15
            Terminal.Parser _ _ parseFunc _ _ = parser
        parseFunc "4" @?= Nothing
        parseFunc "16" @?= Nothing
        parseFunc "-1" @?= Nothing,
      testCase "boolParser rejects invalid boolean representations" $ do
        let parser = Terminal.boolParser
            Terminal.Parser _ _ parseFunc _ _ = parser
        parseFunc "maybe" @?= Nothing
        parseFunc "2" @?= Nothing
        parseFunc "True" @?= Nothing -- Case sensitive
        parseFunc "FALSE" @?= Nothing, -- Case sensitive
      testCase "floatParser rejects non-numeric input" $ do
        let parser = Terminal.floatParser
            Terminal.Parser _ _ parseFunc _ _ = parser
        parseFunc "not-a-float" @?= Nothing
        parseFunc "" @?= Nothing
        parseFunc "1.2.3" @?= Nothing,
      testCase "empty oneOf creates empty Args" $ do
        let combined = Terminal.oneOf []
        case combined of
          Terminal.Args [] -> pure () -- empty oneOf creates empty Args
          _ -> assertFailure "empty oneOf should create empty Args"
    ]
