{-# LANGUAGE OverloadedStrings #-}

-- | Tests for structured JSON encoding of diagnostics.
--
-- Verifies that diagnosticToJson, labeledSpanToJson, and suggestionToJson
-- produce well-formed JSON with all expected fields.
--
-- @since 0.19.2
module Unit.Reporting.DiagnosticJsonTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.List as List
import qualified Json.Encode as Encode
import qualified Reporting.Annotation as Ann
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as Doc
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Reporting.Diagnostic JSON Tests"
    [ diagnosticJsonTests,
      labeledSpanJsonTests,
      suggestionJsonTests
    ]

diagnosticJsonTests :: TestTree
diagnosticJsonTests =
  testGroup
    "diagnosticToJson"
    [ testCase "encodes error code" $
        assertJsonContains (Diag.diagnosticToJson testDiag) "E0401",
      testCase "encodes severity" $
        assertJsonContains (Diag.diagnosticToJson testDiag) "error",
      testCase "encodes title" $
        assertJsonContains (Diag.diagnosticToJson testDiag) "TYPE MISMATCH",
      testCase "encodes summary" $
        assertJsonContains (Diag.diagnosticToJson testDiag) "Expression type mismatch",
      testCase "encodes phase" $
        assertJsonContains (Diag.diagnosticToJson testDiag) "type",
      testCase "encodes primary span label" $
        assertJsonContains (Diag.diagnosticToJson testDiag) "type mismatch",
      testCase "encodes suggestion when added" $ do
        let diag = Diag.addSuggestion testSuggestion testDiag
        assertJsonContains (Diag.diagnosticToJson diag) "String.fromInt",
      testCase "encodes note when added" $ do
        let diag = Diag.addNote "Check your types" testDiag
        assertJsonContains (Diag.diagnosticToJson diag) "Check your types"
    ]

labeledSpanJsonTests :: TestTree
labeledSpanJsonTests =
  testGroup
    "labeledSpanToJson"
    [ testCase "encodes label text" $
        assertJsonContains (Diag.labeledSpanToJson testSpan) "type mismatch",
      testCase "encodes style" $
        assertJsonContains (Diag.labeledSpanToJson testSpan) "primary",
      testCase "encodes secondary style" $ do
        let span_ = Diag.LabeledSpan testRegion "context" Diag.SpanSecondary
        assertJsonContains (Diag.labeledSpanToJson span_) "secondary"
    ]

suggestionJsonTests :: TestTree
suggestionJsonTests =
  testGroup
    "suggestionToJson"
    [ testCase "encodes replacement" $
        assertJsonContains (Diag.suggestionToJson testSuggestion) "String.fromInt x",
      testCase "encodes message" $
        assertJsonContains (Diag.suggestionToJson testSuggestion) "Convert with String.fromInt",
      testCase "encodes confidence" $
        assertJsonContains (Diag.suggestionToJson testSuggestion) "likely"
    ]

-- HELPERS

testRegion :: Ann.Region
testRegion = Ann.Region (Ann.Position 5 10) (Ann.Position 5 20)

testSpan :: Diag.LabeledSpan
testSpan = Diag.LabeledSpan testRegion "type mismatch" Diag.SpanPrimary

testDiag :: Diag.Diagnostic
testDiag =
  Diag.makeDiagnostic
    (Diag.ErrorCode 401)
    Diag.SError
    Diag.PhaseType
    "TYPE MISMATCH"
    "Expression type mismatch"
    testSpan
    (Doc.reflow "The type does not match.")

testSuggestion :: Diag.Suggestion
testSuggestion =
  Diag.Suggestion testRegion "String.fromInt x" "Convert with String.fromInt" Diag.Likely

-- | Assert that encoding a JSON value produces output containing a substring.
assertJsonContains :: Encode.Value -> String -> Assertion
assertJsonContains value substr =
  assertBool
    ("JSON should contain " <> show substr <> " but got: " <> rendered)
    (List.isInfixOf substr rendered)
  where
    rendered = BL.unpack (BB.toLazyByteString (Encode.encode value))
