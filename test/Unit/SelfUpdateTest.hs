{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for SelfUpdate module.
--
-- Tests version comparison logic, platform detection,
-- and configuration handling.
--
-- @since 0.19.2
module Unit.SelfUpdateTest (tests) where

import qualified Canopy.Version as Version
import qualified Data.Map.Strict as Map
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
      testCurrentVersion,
      testDownloadUrls,
      testChecksumVerification,
      testChecksumParsing
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

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Download URL construction
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testDownloadUrls :: TestTree
testDownloadUrls =
  testGroup
    "Download URL construction"
    [ testCase "binary URL contains version" $
        let url = SelfUpdate.binaryUrl v0192 linuxPlatform
         in assertBool "URL should contain version"
              (Text.isInfixOf "0.19.2" url),
      testCase "binary URL contains platform slug" $
        let url = SelfUpdate.binaryUrl v0192 linuxPlatform
         in assertBool "URL should contain platform"
              (Text.isInfixOf "linux-x86_64" url),
      testCase "binary URL has tar.gz extension" $
        let url = SelfUpdate.binaryUrl v0192 linuxPlatform
         in assertBool "URL should end with .tar.gz"
              (Text.isSuffixOf ".tar.gz" url),
      testCase "binary URL starts with release base" $
        let url = SelfUpdate.binaryUrl v0192 linuxPlatform
         in assertBool "URL should start with base"
              (Text.isPrefixOf SelfUpdate.releaseBaseUrl url),
      testCase "binary URL exact format" $
        SelfUpdate.binaryUrl v0192 linuxPlatform
          @?= "https://github.com/canopy-lang/canopy/releases/download/0.19.2/canopy-0.19.2-linux-x86_64.tar.gz",
      testCase "checksum URL contains version" $
        let url = SelfUpdate.checksumUrl v0192
         in assertBool "URL should contain version"
              (Text.isInfixOf "0.19.2" url),
      testCase "checksum URL ends with SHA256SUMS.txt" $
        let url = SelfUpdate.checksumUrl v0192
         in assertBool "URL should end with SHA256SUMS.txt"
              (Text.isSuffixOf "SHA256SUMS.txt" url),
      testCase "checksum URL exact format" $
        SelfUpdate.checksumUrl v0192
          @?= "https://github.com/canopy-lang/canopy/releases/download/0.19.2/SHA256SUMS.txt",
      testCase "darwin platform produces correct URL" $
        SelfUpdate.binaryUrl v0192 darwinPlatform
          @?= "https://github.com/canopy-lang/canopy/releases/download/0.19.2/canopy-0.19.2-darwin-aarch64.tar.gz"
    ]
  where
    v0192 = Version.Version 0 19 2
    linuxPlatform =
      SelfUpdate.PlatformInfo
        { SelfUpdate._platformOS = "linux",
          SelfUpdate._platformArch = "x86_64",
          SelfUpdate._platformSlug = "linux-x86_64"
        }
    darwinPlatform =
      SelfUpdate.PlatformInfo
        { SelfUpdate._platformOS = "darwin",
          SelfUpdate._platformArch = "aarch64",
          SelfUpdate._platformSlug = "darwin-aarch64"
        }

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Checksum verification
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testChecksumVerification :: TestTree
testChecksumVerification =
  testGroup
    "Checksum verification"
    [ testCase "matching checksums verify" $
        SelfUpdate.verifyChecksum sampleHash sampleHash @?= True,
      testCase "case-insensitive verification" $
        SelfUpdate.verifyChecksum (Text.toLower sampleHash) (Text.toUpper sampleHash) @?= True,
      testCase "different checksums fail" $
        SelfUpdate.verifyChecksum sampleHash differentHash @?= False,
      testCase "whitespace is trimmed" $
        SelfUpdate.verifyChecksum ("  " <> sampleHash <> "  ") sampleHash @?= True
    ]
  where
    sampleHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    differentHash = "a3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Checksum file parsing
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testChecksumParsing :: TestTree
testChecksumParsing =
  testGroup
    "Checksum file parsing"
    [ testCase "parses single line" $
        let content = sampleHash <> "  canopy-0.19.2-linux-x86_64.tar.gz"
         in Map.lookup "canopy-0.19.2-linux-x86_64.tar.gz" (SelfUpdate.parseChecksumFile content)
              @?= Just sampleHash,
      testCase "parses multiple lines" $
        let content =
              sampleHash <> "  canopy-0.19.2-linux-x86_64.tar.gz\n"
                <> otherHash <> "  canopy-0.19.2-darwin-x86_64.tar.gz\n"
            parsed = SelfUpdate.parseChecksumFile content
         in Map.size parsed @?= 2,
      testCase "skips malformed lines" $
        let content = "not a valid line\n" <> sampleHash <> "  valid-file.tar.gz"
            parsed = SelfUpdate.parseChecksumFile content
         in Map.size parsed @?= 1,
      testCase "empty file produces empty map" $
        SelfUpdate.parseChecksumFile "" @?= Map.empty,
      testCase "skips lines with non-hex hash" $
        let content = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz  bad.tar.gz"
            parsed = SelfUpdate.parseChecksumFile content
         in Map.size parsed @?= 0
    ]
  where
    sampleHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    otherHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
