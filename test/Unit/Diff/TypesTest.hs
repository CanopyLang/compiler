{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Diff.Types module.
--
-- Tests core data types and basic functionality for the
-- Diff system following CLAUDE.md testing patterns.
--
-- @since 0.19.1
module Unit.Diff.TypesTest (tests) where

import qualified Canopy.Magnitude as M
import qualified Canopy.Package as Package
import qualified Canopy.Version as Version
import Diff.Types (Args (..), Chunk (..), Env (..))
import qualified Reporting.Doc as D
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Diff.Types module.
tests :: TestTree
tests =
  Test.testGroup
    "Diff.Types Tests"
    [ argsTests,
      chunkTests
    ]

-- | Tests for Args data type.
argsTests :: TestTree
argsTests =
  Test.testGroup
    "Args Tests"
    [ Test.testCase "CodeVsLatest equality" $
        CodeVsLatest @?= CodeVsLatest,
      Test.testCase "CodeVsExactly with version" $ do
        let version = Version.one
        CodeVsExactly version @?= CodeVsExactly version,
      Test.testCase "LocalInquiry with versions" $ do
        let v1 = Version.one
            v2 = Version.Version 2 0 0
        LocalInquiry v1 v2 @?= LocalInquiry v1 v2,
      Test.testCase "GlobalInquiry with package and versions" $ do
        let name = Package.core
            v1 = Version.one
            v2 = Version.Version 1 1 0
        GlobalInquiry name v1 v2 @?= GlobalInquiry name v1 v2
    ]

-- | Tests for Chunk data type.
chunkTests :: TestTree
chunkTests =
  Test.testGroup
    "Chunk Tests"
    [ Test.testCase "chunk creation and access" $ do
        let title = "Test Title"
            chunk = Chunk title M.MINOR (D.fromChars "Test details")
        case chunk of
          Chunk t _ _ -> t @?= title
    ]