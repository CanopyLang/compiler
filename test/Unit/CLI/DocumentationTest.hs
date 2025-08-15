{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for CLI.Documentation module.
--
-- Tests documentation formatting functions and help text generation,
-- verifying exact output and proper formatting of CLI help messages.
module Unit.CLI.DocumentationTest (tests) where

import CLI.Documentation (createIntroduction, createOutro, reflowText, stackDocuments)
import qualified Data.List as List
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import qualified Text.PrettyPrint.ANSI.Leijen as P

-- | All unit tests for CLI documentation functionality.
tests :: TestTree
tests =
  testGroup
    "CLI Documentation Tests"
    [ testReflowText,
      testStackDocuments,
      testIntroductionStructure,
      testOutroContent
    ]

-- | Test text reflow functionality.
testReflowText :: TestTree
testReflowText =
  testGroup
    "reflowText function"
    [ testCase "reflows simple text correctly" $ do
        let input = "This is a simple test"
            result = show (reflowText input)
            expected = show (P.fillSep [P.text "This", P.text "is", P.text "a", P.text "simple", P.text "test"])
        result @?= expected,
      testCase "handles empty string" $ do
        let result = show (reflowText "")
            expected = show (P.fillSep [])
        result @?= expected,
      testCase "handles single word" $ do
        let result = show (reflowText "word")
            expected = show (P.fillSep [P.text "word"])
        result @?= expected,
      testCase "handles multiple spaces correctly" $ do
        let input = "word1    word2     word3"
            result = show (reflowText input)
            expected = show (P.fillSep [P.text "word1", P.text "word2", P.text "word3"])
        result @?= expected
    ]

-- | Test document stacking functionality.
testStackDocuments :: TestTree
testStackDocuments =
  testGroup
    "stackDocuments function"
    [ testCase "stacks empty list correctly" $ do
        let result = show (stackDocuments [])
            expected = show (P.vcat [])
        result @?= expected,
      testCase "stacks single document" $ do
        let docs = [P.text "single"]
            result = show (stackDocuments docs)
            expected = show (P.vcat [P.text "single"])
        result @?= expected,
      testCase "stacks multiple documents with spacing" $ do
        let docs = [P.text "first", P.text "second"]
            result = show (stackDocuments docs)
            expected = show (P.vcat [P.text "first", "", P.text "second"])
        result @?= expected,
      testCase "stacks three documents correctly" $ do
        let docs = [P.text "one", P.text "two", P.text "three"]
            result = show (stackDocuments docs)
            expected = show (P.vcat [P.text "one", "", P.text "two", "", P.text "three"])
        result @?= expected
    ]

-- | Test introduction message structure.
testIntroductionStructure :: TestTree
testIntroductionStructure =
  testGroup
    "createIntroduction function"
    [ testCase "introduction is not empty" $ do
        let intro = show createIntroduction
        length intro > 0 @?= True,
      testCase "introduction contains Canopy reference" $ do
        let intro = show createIntroduction
        "Canopy" `List.isInfixOf` intro @?= True,
      testCase "introduction contains guide reference" $ do
        let intro = show createIntroduction
        "guide.canopy-lang.org" `List.isInfixOf` intro @?= True
    ]

-- | Test outro message content.
testOutroContent :: TestTree
testOutroContent =
  testGroup
    "createOutro function"
    [ testCase "outro is not empty" $ do
        let outro = show createOutro
        length outro > 0 @?= True,
      testCase "outro contains slack reference" $ do
        let outro = show createOutro
        "slack" `elem` words outro @?= True,
      testCase "outro contains friendly message" $ do
        let outro = show createOutro
        "friendly" `elem` words outro @?= True
    ]
