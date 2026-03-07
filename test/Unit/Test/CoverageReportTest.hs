{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the terminal-side coverage report generation.
--
-- Validates that 'parseCoverageHits' correctly parses the @__canopy_cov@
-- JSON object emitted by the instrumented JS runtime, and that
-- 'CoverageFormat' types are correctly defined.
--
-- @since 0.19.2
module Unit.Test.CoverageReportTest (tests) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Map.Strict as Map
import qualified Test.Coverage as Coverage
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Test.Coverage"
    [ parseCoverageHitsTests,
      coverageFormatTests
    ]

-- PARSE COVERAGE HITS TESTS

parseCoverageHitsTests :: TestTree
parseCoverageHitsTests =
  testGroup
    "parseCoverageHits"
    [ testCase "empty object yields empty map" $
        Coverage.parseCoverageHits (Aeson.Object KM.empty) @?= Map.empty,
      testCase "non-object yields empty map" $
        Coverage.parseCoverageHits Aeson.Null @?= Map.empty,
      testCase "array yields empty map" $
        Coverage.parseCoverageHits (Aeson.Array mempty) @?= Map.empty,
      testCase "string yields empty map" $
        Coverage.parseCoverageHits (Aeson.String "nope") @?= Map.empty,
      testCase "single entry parses correctly" $
        let json = Aeson.object [("0", Aeson.Number 3)]
         in Coverage.parseCoverageHits json @?= Map.singleton 0 3,
      testCase "multiple entries parse correctly" $
        let json = Aeson.object [("0", Aeson.Number 1), ("1", Aeson.Number 0), ("5", Aeson.Number 12)]
            expected = Map.fromList [(0, 1), (1, 0), (5, 12)]
         in Coverage.parseCoverageHits json @?= expected,
      testCase "non-numeric key is skipped" $
        let json = Aeson.object [("abc", Aeson.Number 5), ("0", Aeson.Number 2)]
         in Coverage.parseCoverageHits json @?= Map.singleton 0 2,
      testCase "non-numeric value is skipped" $
        let json = Aeson.object [("0", Aeson.String "bad"), ("1", Aeson.Number 7)]
         in Coverage.parseCoverageHits json @?= Map.singleton 1 7,
      testCase "large hit counts are preserved" $
        let json = Aeson.object [("99", Aeson.Number 10000)]
         in Coverage.parseCoverageHits json @?= Map.singleton 99 10000,
      testCase "zero hit count is preserved" $
        let json = Aeson.object [("3", Aeson.Number 0)]
         in Coverage.parseCoverageHits json @?= Map.singleton 3 0
    ]

-- COVERAGE FORMAT TESTS

coverageFormatTests :: TestTree
coverageFormatTests =
  testGroup
    "CoverageFormat"
    [ testCase "Istanbul show" $
        show Coverage.Istanbul @?= "Istanbul",
      testCase "LCOV show" $
        show Coverage.LCOV @?= "LCOV",
      testCase "Istanbul and LCOV are distinct" $
        assertBool "formats should differ" (Coverage.Istanbul /= Coverage.LCOV),
      testCase "Istanbul equals itself" $
        Coverage.Istanbul @?= Coverage.Istanbul,
      testCase "LCOV equals itself" $
        Coverage.LCOV @?= Coverage.LCOV
    ]
