{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests for Make-related library component interactions.
--
-- Since Make modules are in the terminal executable, these tests focus on
-- integration between library components that the Make system depends on.
-- This ensures that the foundational components work together correctly.
--
-- Key integration scenarios tested:
--   * Cross-component exact value verification
--   * Type conversions and data flow
--   * Consistency across related operations
--
-- @since 0.19.1
module Integration.MakeTest (tests) where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package
import qualified Canopy.Version as Version
import qualified Canopy.Data.Name as Name
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, testCase, (@?=))

-- | All integration tests for Make-related library components.
tests :: TestTree
tests =
  testGroup
    "Make Support Components Integration Tests"
    [ testComponentExactValues,
      testVersionExactValues,
      testModuleNameExactValues,
      testPackageExactValues,
      testNameExactValues,
      testCrossComponentConsistency
    ]

-- | Test exact string values from core component conversions.
testComponentExactValues :: TestTree
testComponentExactValues =
  testGroup
    "Component exact values"
    [ testCase "Version.toChars Version.one" $
        Version.toChars Version.one @?= "1.0.0",
      testCase "Package.toChars Package.core" $
        Package.toChars Package.core @?= "canopy/core",
      testCase "Name.toChars Name._main" $
        Name.toChars Name._main @?= "main",
      testCase "Name.toChars Name.true" $
        Name.toChars Name.true @?= "True",
      testCase "Name.toChars Name.false" $
        Name.toChars Name.false @?= "False"
    ]

-- | Test version exact output.
testVersionExactValues :: TestTree
testVersionExactValues =
  testGroup
    "Version exact values"
    [ testCase "Version.one toChars is 1.0.0" $
        Version.toChars Version.one @?= "1.0.0",
      testCase "Version.one show is deterministic" $ do
        let show1 = show Version.one
            show2 = show Version.one
        assertEqual "show is deterministic" show1 show2
    ]

-- | Test module name exact values.
testModuleNameExactValues :: TestTree
testModuleNameExactValues =
  testGroup
    "ModuleName exact values"
    [ testCase "basics show is deterministic" $ do
        let show1 = show ModuleName.basics
            show2 = show ModuleName.basics
        assertEqual "basics show is deterministic" show1 show2,
      testCase "maybe show is deterministic" $ do
        let show1 = show ModuleName.maybe
            show2 = show ModuleName.maybe
        assertEqual "maybe show is deterministic" show1 show2,
      testCase "basics and maybe are different module names" $
        (ModuleName.basics == ModuleName.maybe) @?= False,
      testCase "basics and list are different module names" $
        (ModuleName.basics == ModuleName.list) @?= False
    ]

-- | Test package exact values.
testPackageExactValues :: TestTree
testPackageExactValues =
  testGroup
    "Package exact values"
    [ testCase "Package.core toChars" $
        Package.toChars Package.core @?= "canopy/core",
      testCase "Package.json toChars" $
        Package.toChars Package.json @?= "canopy/json",
      testCase "Package.html toChars" $
        Package.toChars Package.html @?= "canopy/html",
      testCase "Package.browser toChars" $
        Package.toChars Package.browser @?= "canopy/browser",
      testCase "core and json are different packages" $
        (Package.core == Package.json) @?= False
    ]

-- | Test name exact values.
testNameExactValues :: TestTree
testNameExactValues =
  testGroup
    "Name exact values"
    [ testCase "Name.fromChars roundtrip" $ do
        let input = "testValue"
        Name.toChars (Name.fromChars input) @?= input,
      testCase "Name._main is main" $
        Name.toChars Name._main @?= "main",
      testCase "Name.value is Value" $
        Name.toChars Name.value @?= "Value",
      testCase "Name.identity is identity" $
        Name.toChars Name.identity @?= "identity"
    ]

-- | Test cross-component consistency.
testCrossComponentConsistency :: TestTree
testCrossComponentConsistency =
  testGroup
    "Cross-component consistency"
    [ testCase "build pipeline components produce expected exact values" $ do
        Package.toChars Package.core @?= "canopy/core"
        Version.toChars Version.one @?= "1.0.0"
        Name.toChars Name._main @?= "main",
      testCase "Name.fromChars preserves input" $ do
        let names = ["main", "view", "update", "subscriptions"]
        mapM_ (\n -> Name.toChars (Name.fromChars n) @?= n) names
    ]
