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
    [ testCase "encodes diagnostic fields correctly" $
        render (Diag.diagnosticToJson testDiag)
          @?= "{\n    \"code\": \"E0401\",\n    \"severity\": \"error\",\n    \"title\": \"TYPE MISMATCH\",\n    \"summary\": \"Expression type mismatch\",\n    \"primary\": {\n        \"region\": {\n            \"start\": {\n                \"line\": 5,\n                \"column\": 10\n            },\n            \"end\": {\n                \"line\": 5,\n                \"column\": 20\n            }\n        },\n        \"label\": \"type mismatch\",\n        \"style\": \"primary\"\n    },\n    \"secondary\": [],\n    \"suggestions\": [],\n    \"notes\": [],\n    \"phase\": \"type\",\n    \"message\": [\n        \"The type does not match.\"\n    ]\n}",
      testCase "encodes suggestion when added" $ do
        let diag = Diag.addSuggestion testSuggestion testDiag
            rendered = render (Diag.diagnosticToJson diag)
        rendered @?= "{\n    \"code\": \"E0401\",\n    \"severity\": \"error\",\n    \"title\": \"TYPE MISMATCH\",\n    \"summary\": \"Expression type mismatch\",\n    \"primary\": {\n        \"region\": {\n            \"start\": {\n                \"line\": 5,\n                \"column\": 10\n            },\n            \"end\": {\n                \"line\": 5,\n                \"column\": 20\n            }\n        },\n        \"label\": \"type mismatch\",\n        \"style\": \"primary\"\n    },\n    \"secondary\": [],\n    \"suggestions\": [\n        {\n            \"region\": {\n                \"start\": {\n                    \"line\": 5,\n                    \"column\": 10\n                },\n                \"end\": {\n                    \"line\": 5,\n                    \"column\": 20\n                }\n            },\n            \"replacement\": \"String.fromInt x\",\n            \"message\": \"Convert with String.fromInt\",\n            \"confidence\": \"likely\"\n        }\n    ],\n    \"notes\": [],\n    \"phase\": \"type\",\n    \"message\": [\n        \"The type does not match.\"\n    ]\n}",
      testCase "encodes note when added" $ do
        let diag = Diag.addNote "Check your types" testDiag
            rendered = render (Diag.diagnosticToJson diag)
        rendered @?= "{\n    \"code\": \"E0401\",\n    \"severity\": \"error\",\n    \"title\": \"TYPE MISMATCH\",\n    \"summary\": \"Expression type mismatch\",\n    \"primary\": {\n        \"region\": {\n            \"start\": {\n                \"line\": 5,\n                \"column\": 10\n            },\n            \"end\": {\n                \"line\": 5,\n                \"column\": 20\n            }\n        },\n        \"label\": \"type mismatch\",\n        \"style\": \"primary\"\n    },\n    \"secondary\": [],\n    \"suggestions\": [],\n    \"notes\": [\n        \"Check your types\"\n    ],\n    \"phase\": \"type\",\n    \"message\": [\n        \"The type does not match.\"\n    ]\n}"
    ]

labeledSpanJsonTests :: TestTree
labeledSpanJsonTests =
  testGroup
    "labeledSpanToJson"
    [ testCase "encodes primary span correctly" $
        render (Diag.labeledSpanToJson testSpan)
          @?= "{\n    \"region\": {\n        \"start\": {\n            \"line\": 5,\n            \"column\": 10\n        },\n        \"end\": {\n            \"line\": 5,\n            \"column\": 20\n        }\n    },\n    \"label\": \"type mismatch\",\n    \"style\": \"primary\"\n}",
      testCase "encodes secondary span correctly" $ do
        let span_ = Diag.LabeledSpan testRegion "context" Diag.SpanSecondary
        render (Diag.labeledSpanToJson span_)
          @?= "{\n    \"region\": {\n        \"start\": {\n            \"line\": 5,\n            \"column\": 10\n        },\n        \"end\": {\n            \"line\": 5,\n            \"column\": 20\n        }\n    },\n    \"label\": \"context\",\n    \"style\": \"secondary\"\n}"
    ]

suggestionJsonTests :: TestTree
suggestionJsonTests =
  testGroup
    "suggestionToJson"
    [ testCase "encodes suggestion correctly" $
        render (Diag.suggestionToJson testSuggestion)
          @?= "{\n    \"region\": {\n        \"start\": {\n            \"line\": 5,\n            \"column\": 10\n        },\n        \"end\": {\n            \"line\": 5,\n            \"column\": 20\n        }\n    },\n    \"replacement\": \"String.fromInt x\",\n    \"message\": \"Convert with String.fromInt\",\n    \"confidence\": \"likely\"\n}"
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

-- | Render a JSON value to a String for assertion.
render :: Encode.Value -> String
render = BL.unpack . BB.toLazyByteString . Encode.encode
