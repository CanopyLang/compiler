{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Make-related library components.
--
-- Since Make modules are in the terminal executable and not exposed from
-- the library, these tests focus on testing the supporting library components
-- that Make depends on, such as Canopy.ModuleName, Canopy.Package, and
-- other core types that are used by the Make system.
--
-- These tests verify actual functionality and behavior - NO MOCK FUNCTIONS.
-- Every test validates real properties and edge cases of the underlying types.
module Unit.MakeTest (tests) where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package
import qualified Canopy.Version as Version
import qualified Canopy.Data.Name as Name
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

-- | All unit tests for Make-related library components.
tests :: TestTree
tests =
  testGroup
    "Make Support Components Tests"
    [ testModuleNameHandling,
      testPackageHandling,
      testVersionHandling,
      testNameHandling
    ]

-- | Test ModuleName functionality used by Make system.
testModuleNameHandling :: TestTree
testModuleNameHandling =
  testGroup
    "ModuleName handling"
    [ testCase "module name toChars works correctly" $ do
        ModuleName.toChars (Name.fromChars "Test.Module") @?= "Test.Module"
        ModuleName.toChars (Name.fromChars "Simple") @?= "Simple",
      testCase "module name toFilePath converts correctly" $ do
        ModuleName.toFilePath (Name.fromChars "Test.Module") @?= "Test/Module"
        ModuleName.toFilePath (Name.fromChars "Simple") @?= "Simple",
      testCase "module name toHyphenPath converts correctly" $ do
        ModuleName.toHyphenPath (Name.fromChars "Test.Module") @?= "Test-Module"
        ModuleName.toHyphenPath (Name.fromChars "Simple") @?= "Simple"
    ]

-- | Test Package functionality used by Make system.
testPackageHandling :: TestTree
testPackageHandling =
  testGroup
    "Package handling"
    [ testCase "package toChars conversion works correctly" $ do
        Package.toChars Package.core @?= "canopy/core"
        Package.toChars Package.browser @?= "canopy/browser"
        Package.toChars Package.html @?= "canopy/html",
      testCase "package toUrl conversion works correctly" $ do
        Package.toUrl Package.core @?= "canopy/core"
        Package.toUrl Package.json @?= "canopy/json",
      testCase "package toFilePath conversion works correctly" $ do
        Package.toFilePath Package.core @?= "canopy/core"
        Package.toFilePath Package.http @?= "canopy/http"
    ]

-- | Test Version functionality used by Make system.
testVersionHandling :: TestTree
testVersionHandling =
  testGroup
    "Version handling"
    [ testCase "version toChars conversion works correctly" $
        ( do
            Version.toChars Version.one @?= "1.0.0"
        ),
      testCase "version bumping functions work correctly" $
        ( do
            "1.0.1" @?= Version.toChars (Version.bumpPatch Version.one)
            Version.toChars (Version.bumpMinor Version.one) @?= "1.1.0"
            Version.toChars (Version.bumpMajor Version.one) @?= "2.0.0"
        )
    ]

-- | Test Name functionality used by Make system.
testNameHandling :: TestTree
testNameHandling =
  testGroup
    "Name handling"
    [ testCase "create name from chars and convert back" $ do
        let original = "main"
            name = Name.fromChars original
            converted = Name.toChars name
        converted @?= original,
      testCase "predefined names have correct string values" $ do
        Name.toChars Name._main @?= "main"
        Name.toChars Name.true @?= "True"
        Name.toChars Name.false @?= "False"
        Name.toChars Name.value @?= "Value"
        Name.toChars Name.identity @?= "identity",
      testCase "name fromChars with empty string" $ do
        let emptyName = Name.fromChars ""
            emptyChars = Name.toChars emptyName
        emptyChars @?= "",
      testCase "name roundtrip property for various inputs" $ do
        let inputs = ["test", "hello", "world", "x", "longername"]
        mapM_
          ( \input -> do
              let name = Name.fromChars input
                  result = Name.toChars name
              result @?= input
          )
          inputs
    ]
