{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for the SelfUpdate family of modules.
--
-- Tests cover version comparison, platform detection, URL construction,
-- checksum verification, cache parsing, and HTTP response parsing.
--
-- @since 0.19.2
module Unit.SelfUpdateTest (tests) where

import qualified Canopy.Version as Version
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBS8
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Time.Clock.POSIX as POSIX
import qualified SelfUpdate
import qualified SelfUpdate.Cache as Cache
import qualified SelfUpdate.Http as Http
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "SelfUpdate Tests"
    [ testVersionComparison
    , testPlatformDetection
    , testFlagConstruction
    , testCurrentVersion
    , testDownloadUrls
    , testChecksumVerification
    , testChecksumParsing
    , testCacheParsing
    , testCacheFreshness
    , testCacheFormatting
    , testHttpResponseParsing
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Version comparison
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testVersionComparison :: TestTree
testVersionComparison =
  testGroup
    "Version comparison"
    [ testCase "same version is UpToDate" $
        SelfUpdate.compareVersions v0191 v0191 @?= SelfUpdate.UpToDate
    , testCase "older current is UpdateAvailable" $
        SelfUpdate.compareVersions v0191 v0192 @?= SelfUpdate.UpdateAvailable v0192
    , testCase "newer current is AheadOfLatest" $
        SelfUpdate.compareVersions v0192 v0191 @?= SelfUpdate.AheadOfLatest
    , testCase "major version difference detected" $
        SelfUpdate.compareVersions v0191 v100 @?= SelfUpdate.UpdateAvailable v100
    , testCase "patch version difference detected" $
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
        assertBool "OS is non-empty" (not (Text.null (SelfUpdate._platformOS platform)))
    , testCase "detected platform has non-empty arch" $ do
        platform <- SelfUpdate.detectPlatform
        assertBool "arch is non-empty" (not (Text.null (SelfUpdate._platformArch platform)))
    , testCase "platform slug is OS dash arch" $ do
        platform <- SelfUpdate.detectPlatform
        let expected = SelfUpdate._platformOS platform <> "-" <> SelfUpdate._platformArch platform
        SelfUpdate._platformSlug platform @?= expected
    , testCase "platform slug starts with OS" $ do
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
    [ testCase "check-only flag stored correctly" $
        SelfUpdate._checkOnly (SelfUpdate.Flags True False) @?= True
    , testCase "force flag stored correctly" $
        SelfUpdate._force (SelfUpdate.Flags False True) @?= True
    , testCase "both flags stored correctly" $ do
        let flags = SelfUpdate.Flags True True
        SelfUpdate._checkOnly flags @?= True
        SelfUpdate._force flags @?= True
    , testCase "show instance" $
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
        SelfUpdate.currentVersion @?= Version.compiler
    , testCase "current version is 0.19.1" $
        SelfUpdate.currentVersion @?= Version.Version 0 19 1
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Download URL construction
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testDownloadUrls :: TestTree
testDownloadUrls =
  testGroup
    "Download URL construction"
    [ testCase "binary URL exact format for linux-x86_64" $
        SelfUpdate.binaryUrl v0192 linuxPlatform
          @?= "https://github.com/canopy-lang/canopy/releases/download/0.19.2/canopy-0.19.2-linux-x86_64.tar.gz"
    , testCase "binary URL exact format for darwin-aarch64" $
        SelfUpdate.binaryUrl v0192 darwinPlatform
          @?= "https://github.com/canopy-lang/canopy/releases/download/0.19.2/canopy-0.19.2-darwin-aarch64.tar.gz"
    , testCase "checksum URL exact format" $
        SelfUpdate.checksumUrl v0192
          @?= "https://github.com/canopy-lang/canopy/releases/download/0.19.2/SHA256SUMS.txt"
    , testCase "binary URL starts with release base URL" $
        assertBool "starts with base"
          (Text.isPrefixOf SelfUpdate.releaseBaseUrl (SelfUpdate.binaryUrl v0192 linuxPlatform))
    , testCase "binary URL ends with .tar.gz" $
        assertBool "ends with .tar.gz"
          (Text.isSuffixOf ".tar.gz" (SelfUpdate.binaryUrl v0192 linuxPlatform))
    , testCase "checksum URL ends with SHA256SUMS.txt" $
        assertBool "ends with SHA256SUMS.txt"
          (Text.isSuffixOf "SHA256SUMS.txt" (SelfUpdate.checksumUrl v0192))
    ]
  where
    v0192 = Version.Version 0 19 2
    linuxPlatform = SelfUpdate.PlatformInfo
      { SelfUpdate._platformOS = "linux"
      , SelfUpdate._platformArch = "x86_64"
      , SelfUpdate._platformSlug = "linux-x86_64"
      }
    darwinPlatform = SelfUpdate.PlatformInfo
      { SelfUpdate._platformOS = "darwin"
      , SelfUpdate._platformArch = "aarch64"
      , SelfUpdate._platformSlug = "darwin-aarch64"
      }

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Checksum verification
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testChecksumVerification :: TestTree
testChecksumVerification =
  testGroup
    "Checksum verification"
    [ testCase "matching checksums verify" $
        SelfUpdate.verifyChecksum sampleHash sampleHash @?= True
    , testCase "case-insensitive: lower actual vs upper expected" $
        SelfUpdate.verifyChecksum (Text.toLower sampleHash) (Text.toUpper sampleHash) @?= True
    , testCase "case-insensitive: upper actual vs lower expected" $
        SelfUpdate.verifyChecksum (Text.toUpper sampleHash) (Text.toLower sampleHash) @?= True
    , testCase "different checksums fail" $
        SelfUpdate.verifyChecksum sampleHash differentHash @?= False
    , testCase "leading/trailing whitespace is trimmed" $
        SelfUpdate.verifyChecksum ("  " <> sampleHash <> "  ") sampleHash @?= True
    , testCase "single character difference fails" $
        SelfUpdate.verifyChecksum sampleHash (Text.cons 'a' (Text.tail sampleHash)) @?= False
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
    [ testCase "parses single valid line" $
        Map.lookup "canopy-0.19.2-linux-x86_64.tar.gz"
          (SelfUpdate.parseChecksumFile singleLine)
          @?= Just sampleHash
    , testCase "parses multiple lines and produces correct count" $
        Map.size (SelfUpdate.parseChecksumFile twoLines) @?= 2
    , testCase "both entries are accessible after multi-line parse" $ do
        let parsed = SelfUpdate.parseChecksumFile twoLines
        Map.lookup "canopy-0.19.2-linux-x86_64.tar.gz" parsed @?= Just sampleHash
        Map.lookup "canopy-0.19.2-darwin-x86_64.tar.gz" parsed @?= Just otherHash
    , testCase "skips malformed lines, keeps valid ones" $
        Map.size (SelfUpdate.parseChecksumFile withBadLine) @?= 1
    , testCase "empty file produces empty map" $
        SelfUpdate.parseChecksumFile "" @?= Map.empty
    , testCase "skips lines with non-hex hash" $
        Map.size (SelfUpdate.parseChecksumFile badHashLine) @?= 0
    , testCase "hash value is stored, not filename" $
        Map.lookup "valid-file.tar.gz" (SelfUpdate.parseChecksumFile singleLine2)
          @?= Just sampleHash
    ]
  where
    sampleHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    otherHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
    singleLine = sampleHash <> "  canopy-0.19.2-linux-x86_64.tar.gz"
    singleLine2 = sampleHash <> "  valid-file.tar.gz"
    twoLines = sampleHash <> "  canopy-0.19.2-linux-x86_64.tar.gz\n"
               <> otherHash <> "  canopy-0.19.2-darwin-x86_64.tar.gz"
    withBadLine = "not a valid line\n" <> sampleHash <> "  valid-file.tar.gz"
    badHashLine = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz  bad.tar.gz"

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Cache line parsing
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testCacheParsing :: TestTree
testCacheParsing =
  testGroup
    "Cache line parsing"
    [ testCase "parses well-formed fresh cache line" $
        Cache.parseCacheLine recentTime wellFormedLine
          @?= Just (Version.Version 0 19 2)
    , testCase "rejects expired cache line" $
        Cache.parseCacheLine expiredTime wellFormedLine
          @?= Nothing
    , testCase "rejects malformed line with no tab" $
        Cache.parseCacheLine recentTime "1234567890 0.19.2" @?= Nothing
    , testCase "rejects line with invalid timestamp" $
        Cache.parseCacheLine recentTime "notanumber\t0.19.2" @?= Nothing
    , testCase "rejects line with invalid version" $
        Cache.parseCacheLine recentTime (freshTs <> "\tbadversion") @?= Nothing
    , testCase "rejects empty string" $
        Cache.parseCacheLine recentTime "" @?= Nothing
    , testCase "strips surrounding whitespace" $
        Cache.parseCacheLine recentTime ("  " <> wellFormedLine <> "  ")
          @?= Just (Version.Version 0 19 2)
    ]
  where
    baseTs :: Integer
    baseTs = 1700000000
    recentTime :: POSIX.POSIXTime
    recentTime = fromInteger baseTs + 3600   -- 1 hour after write
    expiredTime :: POSIX.POSIXTime
    expiredTime = fromInteger baseTs + 100000 -- 27+ hours after write
    freshTs = Text.pack (show baseTs)
    wellFormedLine = freshTs <> "\t0.19.2"

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Cache freshness check
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testCacheFreshness :: TestTree
testCacheFreshness =
  testGroup
    "Cache freshness"
    [ testCase "just-written cache is fresh" $
        Cache.isCacheFresh (fromInteger ts + 1) ts @?= True
    , testCase "23-hour-old cache is fresh" $
        Cache.isCacheFresh (fromInteger ts + 82800) ts @?= True
    , testCase "exactly 24-hour-old cache is stale" $
        Cache.isCacheFresh (fromInteger ts + 86400) ts @?= False
    , testCase "25-hour-old cache is stale" $
        Cache.isCacheFresh (fromInteger ts + 90000) ts @?= False
    ]
  where
    ts :: Integer
    ts = 1700000000

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Cache line formatting
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testCacheFormatting :: TestTree
testCacheFormatting =
  testGroup
    "Cache line formatting"
    [ testCase "format contains the timestamp" $
        assertBool "contains ts"
          (Text.isInfixOf "1700000000" (Cache.formatCacheLine 1700000000 v0191))
    , testCase "format contains the version string" $
        assertBool "contains version"
          (Text.isInfixOf "0.19.1" (Cache.formatCacheLine 1700000000 v0191))
    , testCase "format separates timestamp and version with a tab" $
        Cache.formatCacheLine 1700000000 v0191 @?= "1700000000\t0.19.1"
    , testCase "roundtrip: format then parse recovers the version" $
        let line = Cache.formatCacheLine 1700000000 v0191
            now = fromInteger 1700000000 + 60 :: POSIX.POSIXTime
        in Cache.parseCacheLine now line @?= Just v0191
    ]
  where
    v0191 = Version.Version 0 19 1

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- HTTP response parsing (pure)
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testHttpResponseParsing :: TestTree
testHttpResponseParsing =
  testGroup
    "HTTP release response parsing"
    [ testCase "parses standard tag without v prefix" $
        Http.parseReleaseResponse (releaseJson "0.19.2")
          @?= Right (Version.Version 0 19 2)
    , testCase "parses tag with v prefix" $
        Http.parseReleaseResponse (releaseJson "v0.19.2")
          @?= Right (Version.Version 0 19 2)
    , testCase "parses major.minor.patch 1.0.0" $
        Http.parseReleaseResponse (releaseJson "1.0.0")
          @?= Right (Version.Version 1 0 0)
    , testCase "returns Left for invalid JSON" $
        case Http.parseReleaseResponse "not json" of
          Left _ -> pure ()
          Right v -> assertFailure ("Expected Left, got Right " <> show v)
    , testCase "returns Left for missing tag_name field" $
        case Http.parseReleaseResponse "{\"name\": \"Release\"}" of
          Left _ -> pure ()
          Right v -> assertFailure ("Expected Left, got Right " <> show v)
    , testCase "returns Left for invalid version in tag" $
        case Http.parseReleaseResponse (releaseJson "notaversion") of
          Left _ -> pure ()
          Right v -> assertFailure ("Expected Left, got Right " <> show v)
    , testCase "error message mentions the bad tag" $
        case Http.parseReleaseResponse (releaseJson "v-bad") of
          Left msg -> assertBool "mentions tag" (Text.isInfixOf "-bad" msg)
          Right v -> assertFailure ("Expected Left, got Right " <> show v)
    ]

-- | Construct a minimal GitHub releases API JSON body.
releaseJson :: String -> LBS.ByteString
releaseJson tag =
  LBS8.pack ("{\"tag_name\": \"" <> tag <> "\", \"name\": \"Release\"}")
