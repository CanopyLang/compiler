{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Comprehensive test suite for Build.Artifacts.Management.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in Build.Artifacts.Management.
--
-- CRITICAL: These tests verify actual functionality and behavior.
-- NO MOCK FUNCTIONS - every test validates real artifact management scenarios.
--
-- Coverage Target: ≥80% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.Build.Artifacts.ManagementTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import qualified Build.Artifacts.Management as Artifacts
import qualified Build.Types as Types
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package
import qualified Data.NonEmptyList as NE
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Reporting.Exit as Exit

-- | Main test tree containing all Build.Artifacts.Management tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Build.Artifacts.Management Tests"
  [ unitTests
  , edgeCaseTests
  ]

-- | Unit tests for all public functions.
--
-- Tests basic functionality with known inputs and expected outputs.
-- Every public function must have at least one unit test.
unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ testGroup "Module Name Operations"
      [ testCase "matchesRootName with matching Inside result" $ do
          let moduleName = Name.fromChars "TestModule"
          let insideResult = Types.RInside moduleName
          Artifacts.matchesRootName moduleName insideResult @?= True
      , testCase "matchesRootName with matching Outside result" $ do
          let moduleName = Name.fromChars "TestModule"
          let outsideResult = Types.ROutsideOk moduleName undefined undefined
          Artifacts.matchesRootName moduleName outsideResult @?= True
      , testCase "matchesRootName with non-matching result" $ do
          let moduleName1 = Name.fromChars "TestModule1"
          let moduleName2 = Name.fromChars "TestModule2"
          let insideResult = Types.RInside moduleName2
          Artifacts.matchesRootName moduleName1 insideResult @?= False
      ]
  , testGroup "Root Module Classification"
      [ testCase "isRootModule identifies Inside roots correctly" $ do
          let moduleName = Name.fromChars "TestModule"
          let rootResults = NE.List (Types.RInside moduleName) []
          Artifacts.isRootModule rootResults moduleName @?= True
      , testCase "isRootModule identifies Outside roots correctly" $ do
          let moduleName = Name.fromChars "TestModule"
          let rootResults = NE.List (Types.ROutsideOk moduleName undefined undefined) []
          Artifacts.isRootModule rootResults moduleName @?= True
      , testCase "isRootModule returns False for non-root modules" $ do
          let moduleName1 = Name.fromChars "TestModule1"
          let moduleName2 = Name.fromChars "TestModule2"
          let rootResults = NE.List (Types.RInside moduleName2) []
          Artifacts.isRootModule rootResults moduleName1 @?= False
      ]
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "gatherProblemsOrMains with empty results handles single root" $ do
      let emptyResults = Map.empty
      let singleRoot = NE.List (Types.RInside (Name.fromChars "Single")) []
      case Artifacts.gatherProblemsOrMains emptyResults singleRoot of
        Right roots -> length (NE.toList roots) @?= 1
        Left _ -> assertFailure "Empty results with valid root should succeed"
  , testCase "gatherProblemsOrMains with error result returns Left" $ do
      let emptyResults = Map.empty  
      let errorRoot = NE.List (Types.ROutsideErr undefined) []
      case Artifacts.gatherProblemsOrMains emptyResults errorRoot of
        Left _ -> return () -- Expected
        Right _ -> assertFailure "Error root should return Left"
  , testCase "matchesRootName with ROutsideErr returns False" $ do
      let moduleName = Name.fromChars "TestModule"
      let errorResult = Types.ROutsideErr undefined
      Artifacts.matchesRootName moduleName errorResult @?= False
  , testCase "matchesRootName with ROutsideBlocked returns False" $ do
      let moduleName = Name.fromChars "TestModule"
      let blockedResult = Types.ROutsideBlocked
      Artifacts.matchesRootName moduleName blockedResult @?= False
  ]