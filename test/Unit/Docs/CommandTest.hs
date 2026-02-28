{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the @canopy docs@ command module.
--
-- Validates flag parsing, output format selection, and error type
-- construction for the documentation generation command.
--
-- @since 0.19.2
module Unit.Docs.CommandTest (tests) where

import Docs (Flags (..))
import Docs.Render (OutputFormat (..))
import qualified Reporting.Exit as Exit
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

tests :: TestTree
tests =
  Test.testGroup
    "Docs.Command"
    [ flagTests,
      exitTypeTests
    ]

-- FLAG TESTS

-- | Tests for Flags construction and defaults.
flagTests :: TestTree
flagTests =
  Test.testGroup
    "Flags"
    [ Test.testCase "default flags with no format or output" $
        Flags Nothing Nothing @?= Flags Nothing Nothing,
      Test.testCase "flags with JSON format" $
        Flags (Just JsonFormat) Nothing @?= Flags (Just JsonFormat) Nothing,
      Test.testCase "flags with Markdown format" $
        Flags (Just MarkdownFormat) Nothing @?= Flags (Just MarkdownFormat) Nothing,
      Test.testCase "flags with output path" $
        Flags Nothing (Just "docs.json") @?= Flags Nothing (Just "docs.json"),
      Test.testCase "flags with format and output" $
        Flags (Just MarkdownFormat) (Just "docs.md")
          @?= Flags (Just MarkdownFormat) (Just "docs.md"),
      Test.testCase "flags show instance" $
        show (Flags Nothing Nothing) @?= "Flags {_docsFormat = Nothing, _docsOutput = Nothing}"
    ]

-- EXIT TYPE TESTS

-- | Tests for Docs exit error types.
exitTypeTests :: TestTree
exitTypeTests =
  Test.testGroup
    "Exit.Docs"
    [ Test.testCase "DocsNoOutline show" $
        show Exit.DocsNoOutline @?= "DocsNoOutline",
      Test.testCase "DocsAppNeedsFileNames show" $
        show Exit.DocsAppNeedsFileNames @?= "DocsAppNeedsFileNames",
      Test.testCase "DocsPkgNeedsExposing show" $
        show Exit.DocsPkgNeedsExposing @?= "DocsPkgNeedsExposing",
      Test.testCase "DocsCannotWrite show contains path" $
        let err = Exit.DocsCannotWrite "/tmp/docs.json" "permission denied"
         in show err @?= "DocsCannotWrite \"/tmp/docs.json\" \"permission denied\"",
      Test.testCase "DocsBadDetails show contains path" $
        show (Exit.DocsBadDetails "/project") @?= "DocsBadDetails \"/project\""
    ]
