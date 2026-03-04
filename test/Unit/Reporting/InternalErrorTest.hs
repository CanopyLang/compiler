{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the internal error reporting and recovery system.
--
-- Verifies that 'catchInternalError' correctly catches errors from
-- 'InternalError.report', that non-internal 'ErrorCall' exceptions are
-- re-thrown, that 'isInternalError' identifies structured diagnostics,
-- and that error messages contain actionable information.
--
-- @since 0.19.2
module Unit.Reporting.InternalErrorTest (tests) where

import Control.Exception (ErrorCall (..), evaluate, try)
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Reporting.InternalError as InternalError
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Reporting.InternalError Tests"
    [ catchTests,
      isInternalErrorTests,
      formatTests,
      diagnosticQualityTests
    ]

-- CATCH INTERNAL ERROR

catchTests :: TestTree
catchTests =
  testGroup
    "catchInternalError"
    [ testCase "catches InternalError.report and returns Left" $ do
        result <- InternalError.catchInternalError (evaluate (triggerReport ()))
        assertBool "should be Left" (isLeft result),
      testCase "returns Right on success" $ do
        result <- InternalError.catchInternalError (pure (42 :: Int))
        result @?= Right 42,
      testCase "caught error contains location" $ do
        result <- InternalError.catchInternalError (evaluate (triggerReport ()))
        assertLeftContains "TestModule.testFunction" result,
      testCase "caught error contains message" $ do
        result <- InternalError.catchInternalError (evaluate (triggerReport ()))
        assertLeftContains "test invariant violation" result,
      testCase "caught error contains context" $ do
        result <- InternalError.catchInternalError (evaluate (triggerReport ()))
        assertLeftContains "This is test context" result,
      testCase "re-throws non-internal ErrorCall" $ do
        result <- try (InternalError.catchInternalError (evaluate (error "plain error")))
        assertBool "should re-throw" (isErrorCall result)
    ]

-- IS INTERNAL ERROR

isInternalErrorTests :: TestTree
isInternalErrorTests =
  testGroup
    "isInternalError"
    [ testCase "recognizes report output" $ do
        result <- try (evaluate (InternalError.report "Foo.bar" "test" "ctx" :: ()))
        case result of
          Left (ErrorCallWithLocation errMsg _) ->
            assertBool "should be recognized" (InternalError.isInternalError errMsg)
          Right _ ->
            assertFailure "report should throw",
      testCase "rejects plain error" $
        assertBool "should not match" (not (InternalError.isInternalError "just a normal error")),
      testCase "rejects empty string" $
        assertBool "should not match" (not (InternalError.isInternalError "")),
      testCase "rejects partial prefix" $
        assertBool "should not match" (not (InternalError.isInternalError "══════"))
    ]

-- FORMAT

formatTests :: TestTree
formatTests =
  testGroup
    "error format structure"
    [ testCase "contains separator lines" $ do
        result <- catchReportMessage "Loc.fn" "msg" "ctx"
        assertTextContains "══════" result,
      testCase "contains INTERNAL COMPILER ERROR header" $ do
        result <- catchReportMessage "Loc.fn" "msg" "ctx"
        assertTextContains "INTERNAL COMPILER ERROR in Loc.fn" result,
      testCase "contains bug report URL" $ do
        result <- catchReportMessage "Loc.fn" "msg" "ctx"
        assertTextContains "https://github.com/canopy-lang/canopy/issues" result,
      testCase "contains message" $ do
        result <- catchReportMessage "Loc.fn" "specific error description" "ctx"
        assertTextContains "specific error description" result,
      testCase "contains context" $ do
        result <- catchReportMessage "Loc.fn" "msg" "detailed context about the failure"
        assertTextContains "detailed context about the failure" result
    ]

-- DIAGNOSTIC QUALITY

diagnosticQualityTests :: TestTree
diagnosticQualityTests =
  testGroup
    "diagnostic quality"
    [ testCase "location is qualified module path" $ do
        result <- catchReportMessage "Optimize.Port.toEncoder" "test" "ctx"
        assertTextContains "Optimize.Port.toEncoder" result,
      testCase "message is human-readable" $ do
        result <- catchReportMessage "Loc" "function type reached port encoder" "ctx"
        assertTextContains "function type reached port encoder" result,
      testCase "context explains why it should never happen" $ do
        result <- catchReportMessage "Loc" "msg" "The type checker must reject function types before this code runs."
        assertTextContains "type checker must reject" result,
      testCase "format includes instructions for the user" $ do
        result <- catchReportMessage "Loc" "msg" "ctx"
        assertTextContains "Include the source file" result
    ]

-- HELPERS

-- | Trigger InternalError.report for testing.
triggerReport :: () -> ()
triggerReport _ =
  InternalError.report
    "TestModule.testFunction"
    "test invariant violation"
    "This is test context for the internal error."

-- | Catch a report call and return the error message text.
catchReportMessage :: Text -> Text -> Text -> IO Text
catchReportMessage loc msg ctx = do
  result <- try (evaluate (InternalError.report loc msg ctx :: ()))
  case result of
    Left (ErrorCallWithLocation errMsg _) -> pure (Text.pack errMsg)
    Right _ -> assertFailure "report should throw" >> pure ""

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False

isErrorCall :: Either ErrorCall (Either Text a) -> Bool
isErrorCall (Left _) = True
isErrorCall _ = False

assertLeftContains :: Text -> Either Text a -> IO ()
assertLeftContains needle (Left msg) =
  assertBool
    ("Expected error to contain " <> show needle <> " but got: " <> show (Text.take 200 msg))
    (needle `Text.isInfixOf` msg)
assertLeftContains needle (Right _) =
  assertFailure ("Expected Left containing " <> show needle <> " but got Right")

assertTextContains :: Text -> Text -> IO ()
assertTextContains needle haystack =
  assertBool
    ("Expected text to contain " <> show needle)
    (needle `Text.isInfixOf` haystack)
