{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for CLI.Documentation module.
--
-- Tests documentation formatting functions and help text generation,
-- verifying exact output and proper formatting of CLI help messages.
module Unit.CLI.DocumentationTest (tests) where

import CLI.Documentation (createIntroduction, createOutro, reflowText, stackDocuments)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import qualified Text.PrettyPrint.ANSI.Leijen as PP

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
            expected = show (PP.fillSep [PP.text "This", PP.text "is", PP.text "a", PP.text "simple", PP.text "test"])
        result @?= expected,
      testCase "handles empty string" $ do
        let result = show (reflowText "")
            expected = show (PP.fillSep [])
        result @?= expected,
      testCase "handles single word" $ do
        let result = show (reflowText "word")
            expected = show (PP.fillSep [PP.text "word"])
        result @?= expected,
      testCase "handles multiple spaces correctly" $ do
        let input = "word1    word2     word3"
            result = show (reflowText input)
            expected = show (PP.fillSep [PP.text "word1", PP.text "word2", PP.text "word3"])
        result @?= expected
    ]

-- | Test document stacking functionality.
testStackDocuments :: TestTree
testStackDocuments =
  testGroup
    "stackDocuments function"
    [ testCase "stacks empty list correctly" $ do
        let result = show (stackDocuments [])
            expected = show (PP.vcat [])
        result @?= expected,
      testCase "stacks single document" $ do
        let docs = [PP.text "single"]
            result = show (stackDocuments docs)
            expected = show (PP.vcat [PP.text "single"])
        result @?= expected,
      testCase "stacks multiple documents with spacing" $ do
        let docs = [PP.text "first", PP.text "second"]
            result = show (stackDocuments docs)
            expected = show (PP.vcat [PP.text "first", "", PP.text "second"])
        result @?= expected,
      testCase "stacks three documents correctly" $ do
        let docs = [PP.text "one", PP.text "two", PP.text "three"]
            result = show (stackDocuments docs)
            expected = show (PP.vcat [PP.text "one", "", PP.text "two", "", PP.text "three"])
        result @?= expected
    ]

-- | Test introduction message structure.
testIntroductionStructure :: TestTree
testIntroductionStructure =
  testGroup
    "createIntroduction function"
    [ testCase "introduction has correct exact rendered text" $ do
        let intro = show createIntroduction
        intro @?= "Hi, thank you for trying out\n\ESC[92mCanopy\ESC[0m \ESC[92m0.19.1\ESC[0m.\nI hope you like it!\n\n\ESC[90m-------------------------------------------------------------------------------\ESC[0m\n\ESC[90mI highly recommend working through <https://guide.canopy-lang.org> to get started.\ESC[0m\n\ESC[90mIt teaches many important concepts, including how to use `canopy` in the terminal.\ESC[0m\n\ESC[90m-------------------------------------------------------------------------------\ESC[0m"
    ]

-- | Test outro message content.
testOutroContent :: TestTree
testOutroContent =
  testGroup
    "createOutro function"
    [ testCase "outro has correct exact rendered text" $ do
        let outro = show createOutro
        outro @?= "Be sure to ask on the Canopy\nslack if you run into trouble!\nFolks are friendly and happy to\nhelp out. They hang out there\nbecause it is fun, so be kind to\nget the best results!"
    ]
