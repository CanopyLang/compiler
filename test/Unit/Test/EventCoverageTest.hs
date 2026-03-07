{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the CoverageEvent parsing in the test event system.
--
-- Validates that NDJSON coverage events are correctly parsed via the
-- 'FromJSON' instance, and that 'isCoverageEvent' correctly identifies
-- them.
--
-- @since 0.19.2
module Unit.Test.EventCoverageTest (tests) where

import qualified Data.Aeson as Aeson
import Test.Event (TestEvent (..), ResultStatus (..), isCoverageEvent, isSummaryEvent)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Test.Event (Coverage)"
    [ parseCoverageEventTests,
      isCoverageEventTests
    ]

-- PARSE COVERAGE EVENT TESTS

parseCoverageEventTests :: TestTree
parseCoverageEventTests =
  testGroup
    "parseCoverageEvent"
    [ testCase "coverage event with data field parses" $
        let json = Aeson.object [("event", "coverage"), ("data", Aeson.object [("0", Aeson.Number 3)])]
         in case Aeson.fromJSON json of
              Aeson.Success (CoverageEvent _) -> pure ()
              Aeson.Success other -> assertFailure ("expected CoverageEvent, got " ++ show other)
              Aeson.Error err -> assertFailure ("parse failed: " ++ err),
      testCase "coverage event preserves data payload" $
        let payload = Aeson.object [("0", Aeson.Number 1), ("5", Aeson.Number 12)]
            json = Aeson.object [("event", "coverage"), ("data", payload)]
         in case Aeson.fromJSON json of
              Aeson.Success (CoverageEvent d) -> d @?= payload
              Aeson.Success other -> assertFailure ("expected CoverageEvent, got " ++ show other)
              Aeson.Error err -> assertFailure ("parse failed: " ++ err),
      testCase "coverage event with empty data object parses" $
        let json = Aeson.object [("event", "coverage"), ("data", Aeson.object [])]
         in case Aeson.fromJSON json of
              Aeson.Success (CoverageEvent _) -> pure ()
              _ -> assertFailure "expected successful parse",
      testCase "coverage event without data field fails" $
        let json = Aeson.object [("event", "coverage")]
         in case Aeson.fromJSON json :: Aeson.Result TestEvent of
              Aeson.Error _ -> pure ()
              Aeson.Success _ -> assertFailure "expected parse failure",
      testCase "result event still parses correctly" $
        let json = Aeson.object [("event", "result"), ("status", "passed"), ("name", "my test"), ("duration", Aeson.Number 42)]
         in case Aeson.fromJSON json of
              Aeson.Success (ResultEvent {}) -> pure ()
              _ -> assertFailure "expected ResultEvent",
      testCase "summary event still parses correctly" $
        let json =
              Aeson.object
                [ ("event", "summary"),
                  ("passed", Aeson.Number 5),
                  ("failed", Aeson.Number 0),
                  ("skipped", Aeson.Number 1),
                  ("todo", Aeson.Number 0),
                  ("total", Aeson.Number 6),
                  ("duration", Aeson.Number 1234)
                ]
         in case Aeson.fromJSON json of
              Aeson.Success (SummaryEvent {}) -> pure ()
              _ -> assertFailure "expected SummaryEvent"
    ]

-- IS COVERAGE EVENT TESTS

isCoverageEventTests :: TestTree
isCoverageEventTests =
  testGroup
    "isCoverageEvent"
    [ testCase "CoverageEvent returns True" $
        isCoverageEvent (CoverageEvent Aeson.Null) @?= True,
      testCase "ResultEvent returns False" $
        isCoverageEvent (ResultEvent Passed "x" 0 Nothing) @?= False,
      testCase "SummaryEvent returns False" $
        isCoverageEvent (SummaryEvent 1 0 0 0 1 100) @?= False,
      testCase "isSummaryEvent on CoverageEvent returns False" $
        isSummaryEvent (CoverageEvent Aeson.Null) @?= False
    ]
