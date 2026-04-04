{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Builder.LockFile module.
--
-- Tests lock file serialization, staleness detection, and generation.
--
-- @since 0.19.1
module Unit.Builder.LockFileTest (tests) where

import qualified Builder.LockFile as LockFile
import qualified Builder.LockFile.Types as LFT
import Canopy.Package (Name (..))
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Canopy.Data.Utf8 as Utf8
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Builder.LockFile Tests"
    [ testWriteReadRoundtrip,
      testStalenessDetection,
      testReadMissing,
      testGenerateAndRead,
      testLockFilePath,
      testEmptyPackagesRoundtrip,
      testCurrentLockFile,
      testUncachedPackageHash,
      testGeneratedHashFormat,
      testMultiPackageLockFile,
      testLockFileOverwrite,
      testLockFilePackageFields,
      testContentHashEquality
    ]

-- | Make a test package name from author/project strings.
mkPkg :: String -> String -> Pkg.Name
mkPkg author project =
  Name (Utf8.fromChars author) (Utf8.fromChars project)

-- | Make a test version.
mkVer :: Int -> Int -> Int -> Version.Version
mkVer major minor patch = Version.Version (fromIntegral major) (fromIntegral minor) (fromIntegral patch)

-- | Create a sample lock file for testing.
sampleLockFile :: LockFile.LockFile
sampleLockFile =
  LockFile.LockFile
    { LockFile._lockVersion = 1,
      LockFile._lockGenerated = LFT.mkTimestamp "2026-02-27T12:00:00Z",
      LockFile._lockRootHash = LFT.unsafeContentHash "sha256:abc123",
      LockFile._lockPackages = samplePackages
    }

samplePackages :: Map Pkg.Name LockFile.LockedPackage
samplePackages =
  Map.fromList
    [ ( mkPkg "elm" "core",
        LockFile.LockedPackage
          { LockFile._lpVersion = mkVer 1 0 5,
            LockFile._lpHash = LFT.unsafeContentHash "sha256:def456",
            LockFile._lpDependencies = Map.empty,
            LockFile._lpSignature = Nothing,
            LockFile._lpSource = Nothing
          }
      ),
      ( mkPkg "elm" "json",
        LockFile.LockedPackage
          { LockFile._lpVersion = mkVer 1 1 3,
            LockFile._lpHash = LFT.unsafeContentHash "sha256:ghi789",
            LockFile._lpDependencies = Map.singleton (mkPkg "elm" "core") (mkVer 1 0 5),
            LockFile._lpSignature = Nothing,
            LockFile._lpSource = Nothing
          }
      )
    ]

testWriteReadRoundtrip :: TestTree
testWriteReadRoundtrip =
  testGroup
    "write/read roundtrip"
    [ testCase "roundtrip preserves lock file version" $
        withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
          LockFile.writeLockFile tmpDir sampleLockFile
          result <- LockFile.readLockFile tmpDir
          fmap LockFile._lockVersion result @?= Just 1,
      testCase "roundtrip preserves generated timestamp" $
        withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
          LockFile.writeLockFile tmpDir sampleLockFile
          result <- LockFile.readLockFile tmpDir
          fmap (LFT.unTimestamp . LockFile._lockGenerated) result @?= Just "2026-02-27T12:00:00Z",
      testCase "roundtrip preserves root hash" $
        withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
          LockFile.writeLockFile tmpDir sampleLockFile
          result <- LockFile.readLockFile tmpDir
          fmap (LFT.unContentHash . LockFile._lockRootHash) result @?= Just "sha256:abc123",
      testCase "roundtrip preserves package count" $
        withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
          LockFile.writeLockFile tmpDir sampleLockFile
          result <- LockFile.readLockFile tmpDir
          fmap (Map.size . LockFile._lockPackages) result @?= Just 2,
      testCase "roundtrip preserves package versions" $
        withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
          LockFile.writeLockFile tmpDir sampleLockFile
          result <- LockFile.readLockFile tmpDir
          let corePkg = result >>= Map.lookup (mkPkg "elm" "core") . LockFile._lockPackages
          fmap LockFile._lpVersion corePkg @?= Just (mkVer 1 0 5),
      testCase "roundtrip preserves dependency map" $
        withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
          LockFile.writeLockFile tmpDir sampleLockFile
          result <- LockFile.readLockFile tmpDir
          let jsonPkg = result >>= Map.lookup (mkPkg "elm" "json") . LockFile._lockPackages
          fmap (Map.size . LockFile._lpDependencies) jsonPkg @?= Just 1
    ]

testStalenessDetection :: TestTree
testStalenessDetection =
  testGroup
    "staleness detection"
    [ testCase "lock file is stale when canopy.json is missing" $
        withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
          current <- LockFile.isLockFileCurrent sampleLockFile tmpDir
          current @?= False,
      testCase "lock file is stale when hash does not match" $
        withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
          writeFile (tmpDir </> "canopy.json") "{\"type\":\"application\"}"
          current <- LockFile.isLockFileCurrent sampleLockFile tmpDir
          current @?= False
    ]

testReadMissing :: TestTree
testReadMissing =
  testCase "reading missing lock file returns Nothing" $
    withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
      result <- LockFile.readLockFile tmpDir
      assertBool "expected Nothing for missing lock file" (isNothing result)

isNothing :: Maybe a -> Bool
isNothing Nothing = True
isNothing (Just _) = False

testGenerateAndRead :: TestTree
testGenerateAndRead =
  testCase "generate then read produces valid lock file" $
    withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
      writeFile (tmpDir </> "canopy.json") "{\"type\":\"application\"}"
      let deps = Map.singleton (mkPkg "elm" "core") (mkVer 1 0 5)
      LockFile.generateLockFile tmpDir deps
      result <- LockFile.readLockFile tmpDir
      case result of
        Nothing -> assertFailure "Expected lock file to be readable"
        Just lf -> do
          LockFile._lockVersion lf @?= 1
          Map.size (LockFile._lockPackages lf) @?= 1

testLockFilePath :: TestTree
testLockFilePath =
  testCase "lockFilePath appends canopy.lock" $
    LockFile.lockFilePath "/project/root" @?= "/project/root/canopy.lock"

testEmptyPackagesRoundtrip :: TestTree
testEmptyPackagesRoundtrip =
  testCase "lock file with no packages roundtrips" $
    withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
      let lf =
            LockFile.LockFile
              { LockFile._lockVersion = 1,
                LockFile._lockGenerated = LFT.mkTimestamp "2026-01-01T00:00:00Z",
                LockFile._lockRootHash = LFT.unsafeContentHash "sha256:empty",
                LockFile._lockPackages = Map.empty
              }
      LockFile.writeLockFile tmpDir lf
      result <- LockFile.readLockFile tmpDir
      fmap (Map.size . LockFile._lockPackages) result @?= Just 0

testCurrentLockFile :: TestTree
testCurrentLockFile =
  testCase "generated lock file is current with canopy.json" $
    withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
      writeFile (tmpDir </> "canopy.json") "{\"type\":\"application\"}"
      let deps = Map.singleton (mkPkg "elm" "core") (mkVer 1 0 5)
      LockFile.generateLockFile tmpDir deps
      result <- LockFile.readLockFile tmpDir
      case result of
        Nothing -> assertFailure "Expected lock file to be readable"
        Just lf -> do
          current <- LockFile.isLockFileCurrent lf tmpDir
          current @?= True

testUncachedPackageHash :: TestTree
testUncachedPackageHash =
  testCase "uncached package gets sha256:not-cached hash" $
    withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
      writeFile (tmpDir </> "canopy.json") "{\"type\":\"application\"}"
      let fakePkg = mkPkg "nonexistent" "package"
          deps = Map.singleton fakePkg (mkVer 99 99 99)
      LockFile.generateLockFile tmpDir deps
      result <- LockFile.readLockFile tmpDir
      case result of
        Nothing -> assertFailure "Expected lock file to be readable"
        Just lf ->
          case Map.lookup fakePkg (LockFile._lockPackages lf) of
            Nothing -> assertFailure "Expected package in lock file"
            Just lp -> LockFile._lpHash lp @?= LFT.notCachedHash

testGeneratedHashFormat :: TestTree
testGeneratedHashFormat =
  testCase "generated root hash starts with sha256: prefix" $
    withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
      writeFile (tmpDir </> "canopy.json") "{\"type\":\"application\"}"
      LockFile.generateLockFile tmpDir Map.empty
      result <- LockFile.readLockFile tmpDir
      case result of
        Nothing -> assertFailure "Expected lock file to be readable"
        Just lf -> do
          let rootHash = LFT.unContentHash (LockFile._lockRootHash lf)
          assertBool
            "root hash should start with sha256:"
            (Text.isPrefixOf "sha256:" rootHash)
          assertBool
            "root hash should have hex digits after prefix"
            (Text.length rootHash > Text.length "sha256:")

testMultiPackageLockFile :: TestTree
testMultiPackageLockFile =
  testCase "lock file with three packages roundtrips" $
    withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
      let lf = LockFile.LockFile
            { LockFile._lockVersion = 1
            , LockFile._lockGenerated = LFT.mkTimestamp "2026-01-01T00:00:00Z"
            , LockFile._lockRootHash = LFT.unsafeContentHash "sha256:multi"
            , LockFile._lockPackages = threePackages
            }
      LockFile.writeLockFile tmpDir lf
      result <- LockFile.readLockFile tmpDir
      fmap (Map.size . LockFile._lockPackages) result @?= Just 3
  where
    threePackages =
      Map.fromList
        [ (mkPkg "elm" "core", mkLockedPkg (mkVer 1 0 5))
        , (mkPkg "elm" "json", mkLockedPkg (mkVer 1 1 3))
        , (mkPkg "elm" "html", mkLockedPkg (mkVer 1 0 0))
        ]
    mkLockedPkg ver =
      LockFile.LockedPackage
        { LockFile._lpVersion = ver
        , LockFile._lpHash = LFT.unsafeContentHash "sha256:x"
        , LockFile._lpDependencies = Map.empty
        , LockFile._lpSignature = Nothing
        , LockFile._lpSource = Nothing
        }

testLockFileOverwrite :: TestTree
testLockFileOverwrite =
  testCase "writing twice overwrites previous lock file" $
    withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
      let lf1 = LockFile.LockFile 1 (LFT.mkTimestamp "2026-01-01T00:00:00Z") (LFT.unsafeContentHash "sha256:first") Map.empty
          lf2 = LockFile.LockFile 2 (LFT.mkTimestamp "2026-06-01T00:00:00Z") (LFT.unsafeContentHash "sha256:second") Map.empty
      LockFile.writeLockFile tmpDir lf1
      LockFile.writeLockFile tmpDir lf2
      result <- LockFile.readLockFile tmpDir
      fmap LockFile._lockVersion result @?= Just 2

testLockFilePackageFields :: TestTree
testLockFilePackageFields =
  testCase "locked package dependency and hash fields roundtrip" $
    withSystemTempDirectory "lockfile-test" $ \tmpDir -> do
      let dep = Map.singleton (mkPkg "elm" "core") (mkVer 1 0 5)
          pkg = LockFile.LockedPackage
            { LockFile._lpVersion = mkVer 2 0 0
            , LockFile._lpHash = LFT.unsafeContentHash "sha256:mypkg"
            , LockFile._lpDependencies = dep
            , LockFile._lpSignature = Nothing
            , LockFile._lpSource = Nothing
            }
          lf = LockFile.LockFile 1 (LFT.mkTimestamp "2026-01-01T00:00:00Z") (LFT.unsafeContentHash "sha256:root") (Map.singleton (mkPkg "author" "pkg") pkg)
      LockFile.writeLockFile tmpDir lf
      result <- LockFile.readLockFile tmpDir
      let loaded = result >>= Map.lookup (mkPkg "author" "pkg") . LockFile._lockPackages
      fmap (Map.size . LockFile._lpDependencies) loaded @?= Just 1

testContentHashEquality :: TestTree
testContentHashEquality =
  testGroup
    "ContentHash equality"
    [ testCase "same unsafeContentHash values are equal" $
        LFT.unsafeContentHash "sha256:abc" @?= LFT.unsafeContentHash "sha256:abc",
      testCase "different unsafeContentHash values are not equal" $
        assertBool "different hashes" (LFT.unsafeContentHash "sha256:a" /= LFT.unsafeContentHash "sha256:b"),
      testCase "notCachedHash has sha256: prefix" $
        assertBool "not-cached hash has prefix"
          (Text.isPrefixOf "sha256:" (LFT.unContentHash LFT.notCachedHash))
    ]
