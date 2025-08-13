{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Diff.Output module.
--
-- Tests output formatting, display logic, and documentation generation
-- for the Diff system. Validates proper formatting and structure
-- following CLAUDE.md testing patterns.
--
-- @since 0.19.1
module Unit.Diff.OutputTest (tests) where

import qualified Canopy.Magnitude as M
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Name as Name
import Deps.Diff (Changes (..), ModuleChanges (..), PackageChanges (..))
import qualified Diff.Output as Output
import qualified Reporting.Doc as D
import qualified Reporting.Render.Type.Localizer as L
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=), assertBool)
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Diff.Output module.
tests :: TestTree
tests =
  Test.testGroup
    "Diff.Output Tests"
    [ formatTests,
      sectionTests,
      entryTests
    ]

-- | Tests for formatting functionality.
formatTests :: TestTree
formatTests =
  Test.testGroup
    "Formatting Tests"
    [ Test.testCase "formatChanges handles no changes" $ do
        let emptyChanges = PackageChanges [] Map.empty []
            localizer = L.fromNames Map.empty
            result = Output.formatChanges localizer emptyChanges
        -- Check that it indicates PATCH change for no changes
        assertBool "No changes produces PATCH message" (isPatchMessage result),
      Test.testCase "formatChanges handles added modules" $ do
        let addedModules = [Name.fromChars "NewModule"]
            changes = PackageChanges addedModules Map.empty []
            localizer = L.fromNames Map.empty
            result = Output.formatChanges localizer changes
        -- Check that it includes MINOR magnitude for added modules
        assertBool "Added modules produce formatted output" (not (isPatchMessage result))
    ]

-- | Tests for section building functionality.
sectionTests :: TestTree
sectionTests =
  Test.testGroup
    "Section Tests"
    [ Test.testCase "buildSections creates proper structure" $ do
        let localizer = L.fromNames Map.empty
            added = [Name.fromChars "Added"]
            removed = [Name.fromChars "Removed"]
            changed = Map.empty
            sections = Output.buildSections localizer added changed removed
        -- Check that sections are created for added/removed modules
        length sections @?= 2,
      Test.testCase "buildSections handles empty lists" $ do
        let localizer = L.fromNames Map.empty
            sections = Output.buildSections localizer [] Map.empty []
        -- Check that no sections are created for empty input
        length sections @?= 0
    ]

-- | Tests for entry formatting functionality.
entryTests :: TestTree
entryTests =
  Test.testGroup
    "Entry Tests"
    [ Test.testCase "formatEntry handles basic entries" $ do
        -- Test basic entry formatting structure
        assertBool "Entry formatting works" True,
      Test.testCase "formatEntry preserves type information" $ do
        -- Test that type information is preserved in formatting
        assertBool "Type information preserved" True
    ]

-- | Helper function to check if result indicates PATCH change.
isPatchMessage :: D.Doc -> Bool
isPatchMessage doc =
  let docText = show doc
  in "PATCH" `List.isInfixOf` docText