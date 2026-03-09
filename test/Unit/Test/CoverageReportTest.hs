{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the terminal-side coverage report generation.
--
-- Validates that 'parseCoverageHits' correctly parses the @__canopy_cov@
-- JSON object emitted by the instrumented JS runtime, that
-- 'CoverageFormat' types are correctly defined, and that
-- 'checkThreshold' returns correct pass/fail results.
--
-- @since 0.19.2
module Unit.Test.CoverageReportTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Map.Strict as Map
import qualified Generate.JavaScript.Coverage as Coverage
import qualified Reporting.Annotation as Ann
import qualified Test.Coverage as TCoverage
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Test.Coverage"
    [ parseCoverageHitsTests,
      coverageFormatTests,
      thresholdTests
    ]

-- PARSE COVERAGE HITS TESTS

parseCoverageHitsTests :: TestTree
parseCoverageHitsTests =
  testGroup
    "parseCoverageHits"
    [ testCase "empty object yields empty map" $
        TCoverage.parseCoverageHits (Aeson.Object KM.empty) @?= Map.empty,
      testCase "non-object yields empty map" $
        TCoverage.parseCoverageHits Aeson.Null @?= Map.empty,
      testCase "array yields empty map" $
        TCoverage.parseCoverageHits (Aeson.Array mempty) @?= Map.empty,
      testCase "string yields empty map" $
        TCoverage.parseCoverageHits (Aeson.String "nope") @?= Map.empty,
      testCase "single entry parses correctly" $
        let json = Aeson.object [("0", Aeson.Number 3)]
         in TCoverage.parseCoverageHits json @?= Map.singleton 0 3,
      testCase "multiple entries parse correctly" $
        let json = Aeson.object [("0", Aeson.Number 1), ("1", Aeson.Number 0), ("5", Aeson.Number 12)]
            expected = Map.fromList [(0, 1), (1, 0), (5, 12)]
         in TCoverage.parseCoverageHits json @?= expected,
      testCase "non-numeric key is skipped" $
        let json = Aeson.object [("abc", Aeson.Number 5), ("0", Aeson.Number 2)]
         in TCoverage.parseCoverageHits json @?= Map.singleton 0 2,
      testCase "non-numeric value is skipped" $
        let json = Aeson.object [("0", Aeson.String "bad"), ("1", Aeson.Number 7)]
         in TCoverage.parseCoverageHits json @?= Map.singleton 1 7,
      testCase "large hit counts are preserved" $
        let json = Aeson.object [("99", Aeson.Number 10000)]
         in TCoverage.parseCoverageHits json @?= Map.singleton 99 10000,
      testCase "zero hit count is preserved" $
        let json = Aeson.object [("3", Aeson.Number 0)]
         in TCoverage.parseCoverageHits json @?= Map.singleton 3 0
    ]

-- COVERAGE FORMAT TESTS

coverageFormatTests :: TestTree
coverageFormatTests =
  testGroup
    "CoverageFormat"
    [ testCase "Istanbul show" $
        show TCoverage.Istanbul @?= "Istanbul",
      testCase "LCOV show" $
        show TCoverage.LCOV @?= "LCOV",
      testCase "Istanbul and LCOV are distinct" $
        assertBool "formats should differ" (TCoverage.Istanbul /= TCoverage.LCOV),
      testCase "Istanbul equals itself" $
        TCoverage.Istanbul @?= TCoverage.Istanbul,
      testCase "LCOV equals itself" $
        TCoverage.LCOV @?= TCoverage.LCOV
    ]

-- THRESHOLD TESTS

nameStr :: String -> Name.Name
nameStr = Name.fromChars

mkPoint :: Int -> String -> String -> Coverage.CoveragePoint
mkPoint covId modName defName =
  Coverage.CoveragePoint covId (nameStr modName) (nameStr defName) defaultRegion Coverage.FunctionEntry dummyCanonical
  where
    defaultRegion = Ann.Region (Ann.Position 1 1) (Ann.Position 1 1)
    dummyCanonical = ModuleName.Canonical Pkg.dummyName (nameStr "Test")

thresholdTests :: TestTree
thresholdTests =
  testGroup
    "checkThreshold"
    [ testCase "coverage above threshold returns True" $
        let covMap = Coverage.CoverageMap (Map.fromList [(0, mkPoint 0 "M" "a"), (1, mkPoint 1 "M" "b")])
            hits = Map.fromList [(0, 1), (1, 1)]
         in TCoverage.checkThreshold 80 Nothing covMap hits @?= True,
      testCase "coverage below threshold returns False" $
        let covMap = Coverage.CoverageMap (Map.fromList [(0, mkPoint 0 "M" "a"), (1, mkPoint 1 "M" "b"), (2, mkPoint 2 "M" "c")])
            hits = Map.singleton 0 1
         in TCoverage.checkThreshold 80 Nothing covMap hits @?= False,
      testCase "coverage exactly at threshold returns True" $
        let covMap = Coverage.CoverageMap (Map.fromList [(0, mkPoint 0 "M" "a"), (1, mkPoint 1 "M" "b")])
            hits = Map.fromList [(0, 1), (1, 1)]
         in TCoverage.checkThreshold 100 Nothing covMap hits @?= True,
      testCase "empty map with any threshold returns True" $
        TCoverage.checkThreshold 80 Nothing (Coverage.CoverageMap Map.empty) Map.empty @?= True
    ]
