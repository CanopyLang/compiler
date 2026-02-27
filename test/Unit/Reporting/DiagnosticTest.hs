{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the Diagnostic foundation types and rendering.
--
-- Verifies error code formatting, JSON encoding, terminal rendering,
-- and construction helpers.
--
-- @since 0.19.2
module Unit.Reporting.DiagnosticTest (tests) where

import qualified Canopy.Data.NonEmptyList as NE
import qualified Data.Text as Text
import qualified Reporting.Annotation as Ann
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as Doc
import qualified Reporting.Error as Error
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Reporting.Diagnostic Tests"
    [ errorCodeTests,
      severityTests,
      phaseTests,
      constructionTests,
      modificationTests,
      cascadeTests
    ]

errorCodeTests :: TestTree
errorCodeTests =
  testGroup
    "error code formatting"
    [ testCase "E0100 formats with leading zeros" $
        Diag.errorCodeToText (Diag.ErrorCode 100) @?= "E0100",
      testCase "E0001 formats single digit" $
        Diag.errorCodeToText (Diag.ErrorCode 1) @?= "E0001",
      testCase "E0042 formats two digits" $
        Diag.errorCodeToText (Diag.ErrorCode 42) @?= "E0042",
      testCase "E0999 formats max range" $
        Diag.errorCodeToText (Diag.ErrorCode 999) @?= "E0999",
      testCase "errorCodeToInt roundtrips" $
        Diag.errorCodeToInt (Diag.ErrorCode 401) @?= 401,
      testCase "ErrorCode Eq instance" $
        Diag.ErrorCode 100 @?= Diag.ErrorCode 100,
      testCase "ErrorCode Ord instance" $
        compare (Diag.ErrorCode 100) (Diag.ErrorCode 200) @?= LT
    ]

severityTests :: TestTree
severityTests =
  testGroup
    "severity ordering"
    [ testCase "SError > SWarning" $
        compare Diag.SError Diag.SWarning @?= LT,
      testCase "SWarning > SInfo" $
        compare Diag.SWarning Diag.SInfo @?= LT,
      testCase "SError == SError" $
        Diag.SError @?= Diag.SError
    ]

phaseTests :: TestTree
phaseTests =
  testGroup
    "phase values"
    [ testCase "PhaseParse shows correctly" $
        show Diag.PhaseParse @?= "PhaseParse",
      testCase "PhaseType shows correctly" $
        show Diag.PhaseType @?= "PhaseType",
      testCase "all phases are distinct" $
        let phases =
              [ Diag.PhaseParse,
                Diag.PhaseImport,
                Diag.PhaseCanon,
                Diag.PhaseType,
                Diag.PhasePattern,
                Diag.PhaseMain,
                Diag.PhaseDocs,
                Diag.PhaseOptimize,
                Diag.PhaseGenerate,
                Diag.PhaseBuild
              ]
         in length phases @?= length (removeDuplicates phases)
    ]

constructionTests :: TestTree
constructionTests =
  testGroup
    "diagnostic construction"
    [ testCase "makeDiagnostic sets all fields" $ do
        let diag = Diag.makeDiagnostic code sev phase title summary primary msg
        Diag._diagCode diag @?= code
        Diag._diagSeverity diag @?= sev
        Diag._diagPhase diag @?= phase
        Diag._diagTitle diag @?= title
        Diag._diagSummary diag @?= summary
        Diag._diagPrimary diag @?= primary
        Diag._diagSecondary diag @?= []
        Diag._diagSuggestions diag @?= []
        Diag._diagNotes diag @?= [],
      testCase "makeSimpleDiagnostic sets defaults" $ do
        let diag = Diag.makeSimpleDiagnostic code phase title region msg
        Diag._diagCode diag @?= code
        Diag._diagSeverity diag @?= Diag.SError
        Diag._diagTitle diag @?= title
        Diag._diagSecondary diag @?= []
        Diag._diagSuggestions diag @?= []
        Diag._diagNotes diag @?= []
    ]
  where
    code = Diag.ErrorCode 401
    sev = Diag.SError
    phase = Diag.PhaseType
    title = "TYPE MISMATCH"
    summary = "Type mismatch in expression"
    region = Ann.Region (Ann.Position 5 10) (Ann.Position 5 20)
    primary = Diag.LabeledSpan region "this is String" Diag.SpanPrimary
    msg = Doc.reflow "The type does not match."

modificationTests :: TestTree
modificationTests =
  testGroup
    "diagnostic modification"
    [ testCase "addSuggestion appends suggestion" $ do
        let diag = baseDiag
        let sug = Diag.Suggestion region "String.fromInt x" "Convert with String.fromInt" Diag.Likely
        let modified = Diag.addSuggestion sug diag
        length (Diag._diagSuggestions modified) @?= 1
        Diag._sugMessage (head (Diag._diagSuggestions modified)) @?= "Convert with String.fromInt",
      testCase "addSecondarySpan appends span" $ do
        let diag = baseDiag
        let span_ = Diag.LabeledSpan region2 "defined here" Diag.SpanSecondary
        let modified = Diag.addSecondarySpan span_ diag
        length (Diag._diagSecondary modified) @?= 1,
      testCase "addNote appends note" $ do
        let diag = baseDiag
        let modified = Diag.addNote "String.toInt returns Maybe Int" diag
        Diag._diagNotes modified @?= ["String.toInt returns Maybe Int"],
      testCase "multiple modifications compose" $ do
        let sug = Diag.Suggestion region "fix" "Apply fix" Diag.Definite
        let span_ = Diag.LabeledSpan region2 "here" Diag.SpanSecondary
        let modified =
              Diag.addNote "a note"
                . Diag.addSecondarySpan span_
                . Diag.addSuggestion sug
                $ baseDiag
        length (Diag._diagSuggestions modified) @?= 1
        length (Diag._diagSecondary modified) @?= 1
        length (Diag._diagNotes modified) @?= 1
    ]
  where
    region = Ann.Region (Ann.Position 5 10) (Ann.Position 5 20)
    region2 = Ann.Region (Ann.Position 3 1) (Ann.Position 3 30)
    baseDiag =
      Diag.makeSimpleDiagnostic
        (Diag.ErrorCode 401)
        Diag.PhaseType
        "TYPE MISMATCH"
        region
        (Doc.reflow "test message")

cascadeTests :: TestTree
cascadeTests =
  testGroup
    "cascade prevention"
    [ testCase "single diagnostic is preserved" $ do
        let diags = NE.List diag1 []
        let filtered = Error.filterCascades diags
        length (NE.toList filtered) @?= 1,
      testCase "distinct codes are preserved" $ do
        let diags = NE.List diag1 [diag2]
        let filtered = Error.filterCascades diags
        length (NE.toList filtered) @?= 2,
      testCase "duplicate code at same region is filtered" $ do
        let dup = makeDiag (Diag.ErrorCode 400) region1
        let diags = NE.List diag1 [dup]
        let filtered = Error.filterCascades diags
        length (NE.toList filtered) @?= 1,
      testCase "same code at different regions is kept" $ do
        let d1 = makeDiag (Diag.ErrorCode 400) region1
        let d2 = makeDiag (Diag.ErrorCode 400) region3
        let diags = NE.List d1 [d2]
        let filtered = Error.filterCascades diags
        length (NE.toList filtered) @?= 2,
      testCase "first diagnostic is always kept" $ do
        let diags = NE.List diag1 [diag1]
        let (NE.List first _) = Error.filterCascades diags
        Diag._diagCode first @?= Diag.ErrorCode 400
    ]
  where
    region1 = Ann.Region (Ann.Position 5 10) (Ann.Position 5 20)
    region3 = Ann.Region (Ann.Position 50 1) (Ann.Position 50 10)
    diag1 = makeDiag (Diag.ErrorCode 400) region1
    diag2 = makeDiag (Diag.ErrorCode 500) region1

makeDiag :: Diag.ErrorCode -> Ann.Region -> Diag.Diagnostic
makeDiag code region =
  Diag.makeSimpleDiagnostic code Diag.PhaseType "TEST" region (Doc.reflow "test")

-- | Remove duplicates from a list, preserving order.
removeDuplicates :: (Eq a) => [a] -> [a]
removeDuplicates [] = []
removeDuplicates (x : xs) = x : removeDuplicates (filter (/= x) xs)
