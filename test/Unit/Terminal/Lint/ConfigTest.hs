{-# LANGUAGE OverloadedStrings #-}

-- | Tests for lint configuration loading from canopy.json.
--
-- Verifies that the @\"lints\"@ key in canopy.json is correctly parsed
-- and merged with the default lint configuration.
--
-- @since 0.19.2
module Unit.Terminal.Lint.ConfigTest (tests) where

import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson as Json
import qualified Data.Map.Strict as Map
import Lint.Config (parseLintOverrides)
import Lint.Types
  ( LintConfig (..),
    LintRule (..),
    RuleConfig (..),
    Severity (..),
    ruleFromString,
    ruleToString,
    severityFromString,
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

tests :: TestTree
tests =
  Test.testGroup
    "Lint.Config"
    [ ruleStringConversionTests,
      severityStringTests,
      parseOverridesTests
    ]

-- RULE STRING CONVERSION

ruleStringConversionTests :: TestTree
ruleStringConversionTests =
  Test.testGroup
    "ruleToString / ruleFromString"
    [ Test.testCase "UnusedImport roundtrips" $
        ruleFromString (ruleToString UnusedImport) @?= Just UnusedImport,
      Test.testCase "BooleanCase roundtrips" $
        ruleFromString (ruleToString BooleanCase) @?= Just BooleanCase,
      Test.testCase "MagicNumber roundtrips" $
        ruleFromString (ruleToString MagicNumber) @?= Just MagicNumber,
      Test.testCase "InconsistentNaming roundtrips" $
        ruleFromString (ruleToString InconsistentNaming) @?= Just InconsistentNaming,
      Test.testCase "PartialFunction string is kebab-case" $
        ruleToString PartialFunction @?= "partial-function",
      Test.testCase "TooManyArguments string is kebab-case" $
        ruleToString TooManyArguments @?= "too-many-arguments",
      Test.testCase "unknown rule returns Nothing" $
        ruleFromString "nonexistent-rule" @?= Nothing,
      Test.testCase "empty string returns Nothing" $
        ruleFromString "" @?= Nothing,
      Test.testCase "all 17 rules roundtrip" $
        let allRules =
              [ UnusedImport, BooleanCase, UnnecessaryParens,
                DropConcatOfLists, UseConsOverConcat, MissingTypeAnnotation,
                ShadowedVariable, UnusedLetVariable, PartialFunction,
                UnsafeCoerce, ListAppendInLoop, UnnecessaryLazyPattern,
                StringConcatInLoop, TooManyArguments, LongFunction,
                MagicNumber, InconsistentNaming
              ]
         in map (\r -> ruleFromString (ruleToString r)) allRules
              @?= map Just allRules
    ]

-- SEVERITY STRING PARSING

severityStringTests :: TestTree
severityStringTests =
  Test.testGroup
    "severityFromString"
    [ Test.testCase "off" $
        severityFromString "off" @?= Just Off,
      Test.testCase "info" $
        severityFromString "info" @?= Just SevInfo,
      Test.testCase "warn" $
        severityFromString "warn" @?= Just SevWarning,
      Test.testCase "warning" $
        severityFromString "warning" @?= Just SevWarning,
      Test.testCase "error" $
        severityFromString "error" @?= Just SevError,
      Test.testCase "unknown returns Nothing" $
        severityFromString "critical" @?= Nothing,
      Test.testCase "empty returns Nothing" $
        severityFromString "" @?= Nothing
    ]

-- PARSE OVERRIDES FROM JSON

parseOverridesTests :: TestTree
parseOverridesTests =
  Test.testGroup
    "parseLintOverrides"
    [ Test.testCase "empty object yields no overrides" $
        parseLintOverrides KeyMap.empty @?= [],
      Test.testCase "string severity parses correctly" $
        let obj = KeyMap.fromList [(Key.fromText "unused-import", Json.String "error")]
         in parseLintOverrides obj @?= [(UnusedImport, SevError)],
      Test.testCase "object with level key parses correctly" $
        let inner = Json.Object (KeyMap.fromList [(Key.fromText "level", Json.String "warn")])
            obj = KeyMap.fromList [(Key.fromText "magic-number", inner)]
         in parseLintOverrides obj @?= [(MagicNumber, SevWarning)],
      Test.testCase "off disables rule" $
        let obj = KeyMap.fromList [(Key.fromText "boolean-case", Json.String "off")]
         in parseLintOverrides obj @?= [(BooleanCase, Off)],
      Test.testCase "unknown rule is skipped" $
        let obj = KeyMap.fromList [(Key.fromText "nonexistent", Json.String "error")]
         in parseLintOverrides obj @?= [],
      Test.testCase "unknown severity is skipped" $
        let obj = KeyMap.fromList [(Key.fromText "unused-import", Json.String "critical")]
         in parseLintOverrides obj @?= [],
      Test.testCase "multiple overrides parsed" $
        let obj =
              KeyMap.fromList
                [ (Key.fromText "unused-import", Json.String "error"),
                  (Key.fromText "magic-number", Json.String "off"),
                  (Key.fromText "long-function", Json.String "warn")
                ]
            result = parseLintOverrides obj
         in length result @?= 3,
      Test.testCase "number value is ignored" $
        let obj = KeyMap.fromList [(Key.fromText "unused-import", Json.Number 42)]
         in parseLintOverrides obj @?= [],
      Test.testCase "object without level key is ignored" $
        let inner = Json.Object (KeyMap.fromList [(Key.fromText "max-lines", Json.Number 20)])
            obj = KeyMap.fromList [(Key.fromText "long-function", inner)]
         in parseLintOverrides obj @?= []
    ]
