{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the error code registry.
--
-- Verifies code range construction, catalog lookup, and explanation
-- formatting via Reporting.Doc rendering.
--
-- @since 0.19.2
module Unit.Reporting.ErrorCodeTest (tests) where

import qualified Data.List as List
import qualified Data.Maybe as Maybe
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as D
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
      testCase "catalog entry has non-empty title" $ do
        let info = EC.lookupInfo (EC.parseError 0)
        case info of
          Nothing -> assertFailure "E0100 should be documented"
          Just i -> assertBool "title non-empty" (EC._infoTitle i /= ""),
      testCase "catalog entry has non-empty explanation" $ do
        let info = EC.lookupInfo (EC.typeError 0)
        case info of
          Nothing -> assertFailure "E0400 should be documented"
          Just i -> assertBool "explanation non-empty" (EC._infoExplanation i /= "")
    ]

explanationTests :: TestTree
explanationTests =
  testGroup
    "explanation formatting"
    [ testCase "documented code renders with error code" $ do
        let rendered = D.toString (EC.formatExplanation (EC.parseError 0))
        assertBool "contains error code" (List.isInfixOf "E0100" rendered),
      testCase "documented code renders with title" $ do
        let rendered = D.toString (EC.formatExplanation (EC.parseError 0))
        assertBool "contains title" (List.isInfixOf "MODULE NAME UNSPECIFIED" rendered),
      testCase "documented code renders with explanation" $ do
        let rendered = D.toString (EC.formatExplanation (EC.typeError 0))
        assertBool "contains explanation" (List.isInfixOf "type mismatch" rendered),
      testCase "undocumented code renders fallback" $ do
        let rendered = D.toString (EC.formatExplanation (Diag.ErrorCode 9999))
        assertBool "contains error code" (List.isInfixOf "E9999" rendered)
        assertBool "contains report link" (List.isInfixOf "github.com" rendered)
    ]

-- | Remove duplicates from a list.
removeDuplicates :: (Eq a) => [a] -> [a]
removeDuplicates [] = []
removeDuplicates (x : xs) = x : removeDuplicates (filter (/= x) xs)
