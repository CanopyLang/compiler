{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for SelfUpdate module.
--
-- Tests version comparison logic, platform detection,
-- and configuration handling.
--
-- @since 0.19.2
module Unit.SelfUpdateTest (tests) where

import qualified Canopy.Version as Version
import qualified Data.Text as Text
import qualified SelfUpdate
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "SelfUpdate Tests"
    [ testVersionComparison,
      testPlatformDetection,
      testFlagConstruction,
      testCurrentVersion
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Version comparison
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testVersionComparison :: TestTree
testVersionComparison =
  testGroup
    "Version comparison"
    [ testCase "same version is UpToDate" $
        SelfUpdate.compareVersions v0191 v0191 @?= SelfUpdate.UpToDate,
      testCase "older current is UpdateAvailable" $
        SelfUpdate.compareVersions v0191 v0192 @?= SelfUpdate.UpdateAvailable v0192,
      testCase "newer current is AheadOfLatest" $
        SelfUpdate.compareVersions v0192 v0191 @?= SelfUpdate.AheadOfLatest,
      testCase "major version difference detected" $
        SelfUpdate.compareVersions v0191 v100 @?= SelfUpdate.UpdateAvailable v100,
      testCase "patch version difference detected" $
        SelfUpdate.compareVersions v0191 v0192 @?= SelfUpdate.UpdateAvailable v0192
    ]
  where
    v0191 = Version.Version 0 19 1
    v0192 = Version.Version 0 19 2
    v100 = Version.Version 1 0 0

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Platform detection
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testPlatformDetection :: TestTree
testPlatformDetection =
  testGroup
    "Platform detection"
    [ testCase "detected platform has non-empty OS" $ do
        platform <- SelfUpdate.detectPlatform
        assertBool
          "OS is non-empty"
          (not (Text.null (SelfUpdate._platformOS platform))),
      testCase "detected platform has non-empty arch" $ do
        platform <- SelfUpdate.detectPlatform
        assertBool
          "arch is non-empty"
          (not (Text.null (SelfUpdate._platformArch platform))),
      testCase "platform slug combines OS and arch with dash" $ do
        platform <- SelfUpdate.detectPlatform
        assertBool
          "slug contains dash"
          (Text.isInfixOf "-" (SelfUpdate._platformSlug platform)),
      testCase "platform slug starts with OS" $ do
        platform <- SelfUpdate.detectPlatform
        assertBool
          "slug starts with OS"
          (Text.isPrefixOf (SelfUpdate._platformOS platform) (SelfUpdate._platformSlug platform))
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Flag construction
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testFlagConstruction :: TestTree
testFlagConstruction =
  testGroup
    "Flag construction"
    [ testCase "check-only flag" $
        SelfUpdate.Flags True False @?= SelfUpdate.Flags True False,
      testCase "force flag" $
        SelfUpdate.Flags False True @?= SelfUpdate.Flags False True,
      testCase "both flags" $
        SelfUpdate.Flags True True @?= SelfUpdate.Flags True True,
      testCase "show instance" $
        show (SelfUpdate.Flags True False) @?=
          "Flags {_checkOnly = True, _force = False}"
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Current version
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testCurrentVersion :: TestTree
testCurrentVersion =
  testGroup
    "Current version"
    [ testCase "current version matches compiler version" $
        SelfUpdate.currentVersion @?= Version.compiler,
      testCase "current version is 0.19.1" $
        SelfUpdate.currentVersion @?= Version.Version 0 19 1
    ]
