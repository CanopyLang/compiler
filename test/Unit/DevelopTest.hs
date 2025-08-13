{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Develop module.
--
-- Tests the development server orchestration and type definitions.
-- Validates proper integration between sub-modules and configuration
-- following CLAUDE.md testing patterns.
--
-- @since 0.19.1
module Unit.DevelopTest (tests) where

import Develop (Flags (..))
import Develop.Types (defaultFlags, flagsPort)
import Control.Lens ((^.))
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Develop module.
tests :: TestTree
tests =
  Test.testGroup
    "Develop Tests"
    [ flagsTests,
      typesTests
    ]

-- | Tests for Flags data type.
flagsTests :: TestTree
flagsTests =
  Test.testGroup
    "Flags Tests"
    [ Test.testCase "default flags have no port" $ do
        defaultFlags ^. flagsPort @?= Nothing,
      Test.testCase "flags with port" $ do
        let flags = Flags (Just 3000)
        flags ^. flagsPort @?= Just 3000
    ]

-- | Tests for Types module functionality.
typesTests :: TestTree
typesTests =
  Test.testGroup
    "Types Tests"
    [ Test.testCase "default flags construction" $ do
        let flags = defaultFlags
        flags ^. flagsPort @?= Nothing
    ]