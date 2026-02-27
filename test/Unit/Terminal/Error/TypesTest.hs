{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Terminal.Error.Types module.
--
-- Tests all core error types, lens operations, and error ranking
-- functionality to ensure correct behavior and type safety.
--
-- @since 0.19.1
module Unit.Terminal.Error.TypesTest (tests) where

import Control.Lens ((&), (.~), (^.))
import Terminal.Error.Types
  ( ArgError (..),
    Error (..),
    Expectation (..),
    FlagError (..),
    argErrorRank,
    expectationExamples,
    expectationType,
    getTopArgError,
  )
import Terminal.Internal (Args (..), CompleteArgs (..), Flag (..), Flags (..), Parser (..), RequiredArgs (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Terminal.Error.Types Tests"
    [ testExpectationLenses,
      testArgErrorRanking,
      testTopErrorSelection,
      testErrorTypeEquality,
      testErrorTypeShow
    ]

-- | Test lens operations for Expectation type
testExpectationLenses :: TestTree
testExpectationLenses =
  testGroup
    "Expectation Lens Tests"
    [ testCase "expectationType lens view" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
        expectation ^. expectationType @?= "file",
      testCase "expectationType lens update" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
            updated = expectation & expectationType .~ "number"
        updated ^. expectationType @?= "number",
      testCase "expectationExamples lens access" $ do
        let examples = ["test.txt", "data.csv"]
            expectation = Expectation "file" (pure examples)
        result <- expectation ^. expectationExamples
        result @?= examples,
      testCase "expectationExamples lens update" $ do
        let expectation = Expectation "file" (pure ["old.txt"])
            newExamples = pure ["new.txt", "updated.csv"]
            updated = expectation & expectationExamples .~ newExamples
        result <- updated ^. expectationExamples
        result @?= ["new.txt", "updated.csv"]
    ]

-- | Test argument error ranking system
testArgErrorRanking :: TestTree
testArgErrorRanking =
  testGroup
    "ArgError Ranking Tests"
    [ testCase "ArgBad has highest priority (rank 0)" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
            badError = ArgBad "invalid" expectation
        argErrorRank badError @?= 0,
      testCase "ArgMissing has medium priority (rank 1)" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
            missingError = ArgMissing expectation
        argErrorRank missingError @?= 1,
      testCase "ArgExtras has lowest priority (rank 2)" $ do
        let extrasError = ArgExtras ["extra1", "extra2"]
        argErrorRank extrasError @?= 2,
      testCase "ranking order is consistent" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
            badError = ArgBad "invalid" expectation
            missingError = ArgMissing expectation
            extrasError = ArgExtras ["extra"]
        assertBool
          "ArgBad ranks higher than ArgMissing"
          (argErrorRank badError < argErrorRank missingError)
        assertBool
          "ArgMissing ranks higher than ArgExtras"
          (argErrorRank missingError < argErrorRank extrasError)
    ]

-- | Test top error selection from multiple errors
testTopErrorSelection :: TestTree
testTopErrorSelection =
  testGroup
    "Top Error Selection Tests"
    [ testCase "selects ArgBad when multiple errors present" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
            badError = ArgBad "invalid" expectation
            missingError = ArgMissing expectation
            extrasError = ArgExtras ["extra"]
            parser = Parser "test" "tests" Just (\_ -> pure []) (\_ -> pure ["example"])
            args = Exactly (Done id)
            errors = [(args, missingError), (args, badError), (args, extrasError)]
        getTopArgError errors @?= badError,
      testCase "selects ArgMissing when no ArgBad present" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
            missingError = ArgMissing expectation
            extrasError = ArgExtras ["extra"]
            args = Exactly (Done id)
            errors = [(args, extrasError), (args, missingError)]
        getTopArgError errors @?= missingError,
      testCase "handles single error correctly" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
            singleError = ArgMissing expectation
            args = Exactly (Done id)
            errors = [(args, singleError)]
        getTopArgError errors @?= singleError
    ]

-- | Test error type equality instances
testErrorTypeEquality :: TestTree
testErrorTypeEquality =
  testGroup
    "Error Type Equality Tests"
    [ testCase "Expectation equality based on type only" $ do
        let exp1 = Expectation "file" (pure ["test1.txt"])
            exp2 = Expectation "file" (pure ["test2.txt"])
            exp3 = Expectation "number" (pure ["1", "2"])
        assertBool "Same type expectations are equal" (exp1 == exp2)
        assertBool "Different type expectations are not equal" (exp1 /= exp3),
      testCase "ArgError equality works correctly" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
            error1 = ArgMissing expectation
            error2 = ArgMissing expectation
            error3 = ArgBad "invalid" expectation
        assertBool "Same ArgMissing errors are equal" (error1 == error2)
        assertBool "Different ArgError types are not equal" (error1 /= error3)
    ]

-- | Test error type show instances
testErrorTypeShow :: TestTree
testErrorTypeShow =
  testGroup
    "Error Type Show Tests"
    [ testCase "Expectation show includes type" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
            shown = show expectation
        assertBool "Show includes type name" ("file" `elem` words shown)
        assertBool "Show includes Expectation constructor" ("Expectation" `elem` words shown),
      testCase "ArgError show works for all variants" $ do
        let expectation = Expectation "file" (pure ["test.txt"])
            missingError = ArgMissing expectation
            badError = ArgBad "invalid" expectation
            extrasError = ArgExtras ["extra1", "extra2"]
        assertBool "ArgMissing produces output" (length (show missingError) > 5)
        assertBool "ArgBad produces output" (length (show badError) > 5)
        assertBool "ArgExtras produces output" (length (show extrasError) > 5)
    ]
