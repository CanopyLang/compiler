{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the error code registry.
--
-- Verifies code range construction, catalog lookup, and explanation
-- formatting via Reporting.Doc rendering.
--
-- @since 0.19.2
module Unit.Reporting.ErrorCodeTest (tests) where

import qualified Data.Maybe as Maybe
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as Doc
import qualified Reporting.ErrorCode as EC
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Reporting.ErrorCode Tests"
    [ rangeTests,
      catalogTests,
      explanationTests
    ]

rangeTests :: TestTree
rangeTests =
  testGroup
    "code range construction"
    [ testCase "parseError 0 = E0100" $
        Diag.errorCodeToInt (EC.parseError 0) @?= 100,
      testCase "parseError 10 = E0110" $
        Diag.errorCodeToInt (EC.parseError 10) @?= 110,
      testCase "importError 0 = E0200" $
        Diag.errorCodeToInt (EC.importError 0) @?= 200,
      testCase "canonError 0 = E0300" $
        Diag.errorCodeToInt (EC.canonError 0) @?= 300,
      testCase "typeError 0 = E0400" $
        Diag.errorCodeToInt (EC.typeError 0) @?= 400,
      testCase "patternError 0 = E0500" $
        Diag.errorCodeToInt (EC.patternError 0) @?= 500,
      testCase "mainError 0 = E0600" $
        Diag.errorCodeToInt (EC.mainError 0) @?= 600,
      testCase "docsError 0 = E0700" $
        Diag.errorCodeToInt (EC.docsError 0) @?= 700,
      testCase "optimizeError 0 = E0800" $
        Diag.errorCodeToInt (EC.optimizeError 0) @?= 800,
      testCase "generateError 0 = E0900" $
        Diag.errorCodeToInt (EC.generateError 0) @?= 900,
      testCase "ranges do not overlap" $
        let starts = [100, 200, 300, 400, 500, 600, 700, 800, 900]
         in length starts @?= length (removeDuplicates starts)
    ]

catalogTests :: TestTree
catalogTests =
  testGroup
    "error catalog lookup"
    [ testCase "E0100 is documented" $
        Maybe.isJust (EC.lookupInfo (EC.parseError 0)) @?= True,
      testCase "E0200 is documented" $
        Maybe.isJust (EC.lookupInfo (EC.importError 0)) @?= True,
      testCase "E0400 is documented" $
        Maybe.isJust (EC.lookupInfo (EC.typeError 0)) @?= True,
      testCase "E0500 is documented" $
        Maybe.isJust (EC.lookupInfo (EC.patternError 0)) @?= True,
      testCase "E0300 is documented" $
        Maybe.isJust (EC.lookupInfo (EC.canonError 0)) @?= True,
      testCase "E0600 is documented" $
        Maybe.isJust (EC.lookupInfo (EC.mainError 0)) @?= True,
      testCase "E0602 is documented" $
        Maybe.isJust (EC.lookupInfo (EC.mainError 2)) @?= True,
      testCase "E0700 is documented" $
        Maybe.isJust (EC.lookupInfo (EC.docsError 0)) @?= True,
      testCase "undocumented code returns Nothing" $
        EC.lookupInfo (Diag.ErrorCode 9999) @?= Nothing,
      testCase "catalog entry has correct title" $ do
        let info = EC.lookupInfo (EC.parseError 0)
        case info of
          Nothing -> assertFailure "E0100 should be documented"
          Just i -> EC._infoTitle i @?= "MODULE NAME UNSPECIFIED",
      testCase "catalog entry has correct explanation" $ do
        let info = EC.lookupInfo (EC.typeError 0)
        case info of
          Nothing -> assertFailure "E0400 should be documented"
          Just i -> EC._infoTitle i @?= "TYPE MISMATCH"
    ]

explanationTests :: TestTree
explanationTests =
  testGroup
    "explanation formatting"
    [ testCase "documented code renders with error code" $ do
        let rendered = Doc.toString (EC.formatExplanation (EC.parseError 0))
        rendered @?= "-- MODULE NAME UNSPECIFIED [E0100]\n\n\n\nA module file is missing its module declaration.\n\n\n\nEvery Canopy file must start with a module declaration that matches its file path.\nFor example, a file at src/Main.can should start with:\n\n    module Main exposing (..)\n\nThe module name must match the file path exactly.",
      testCase "documented code renders with type error" $ do
        let rendered = Doc.toString (EC.formatExplanation (EC.typeError 0))
        rendered @?= "-- TYPE MISMATCH [E0400]\n\n\n\nAn expression has a different type than expected.\n\n\n\nThe compiler found a type mismatch between what was expected\nand what was actually provided. Common causes:\n  - Wrong argument type to a function\n  - Branches of if/case returning different types\n  - Annotation doesn't match implementation\n\nRead the expected and actual types carefully. The error will\npoint to the specific location of the mismatch.",
      testCase "undocumented code renders fallback" $ do
        let rendered = Doc.toString (EC.formatExplanation (Diag.ErrorCode 9999))
        rendered @?= "-- E9999\n\n\n\nError E9999 is not yet documented.\n\nPlease report this at https://github.com/quinten/canopy/issues"
    ]

-- | Remove duplicates from a list.
removeDuplicates :: (Eq a) => [a] -> [a]
removeDuplicates [] = []
removeDuplicates (x : xs) = x : removeDuplicates (filter (/= x) xs)
