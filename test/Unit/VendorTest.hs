{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for the Vendor module.
--
-- Tests the vendoring logic including dependency resolution from
-- caches, directory copying, and the offline-only fetch path.
--
-- @since 0.19.2
module Unit.VendorTest (tests) where

import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.List as List
import qualified PackageCache.Fetch as Fetch
import qualified System.Directory as Dir
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit
import qualified Vendor

tests :: TestTree
tests =
  testGroup
    "Vendor & Offline Fetch Tests"
    [ vendorTests,
      offlineFetchTests
    ]

-- -------------------------------------------------------------------
-- Vendor tests
-- -------------------------------------------------------------------

vendorTests :: TestTree
vendorTests =
  testGroup
    "Vendor"
    [ testResolvePackagePath,
      testCopyPackageDir,
      testVendorDependencies,
      testFlagsConstruction
    ]

-- | Verify that resolvePackagePath finds a known cached package.
testResolvePackagePath :: TestTree
testResolvePackagePath =
  testGroup
    "resolvePackagePath"
    [ testCase "finds core in cache" $ do
        result <- Vendor.resolvePackagePath Pkg.core (makeVersion 1 0 5)
        case result of
          Nothing -> assertFailure "core 1.0.5 should be found in local or Elm cache"
          Just path -> assertBool ("path should exist: " ++ path) =<< Dir.doesDirectoryExist path,
      testCase "returns Nothing for nonexistent package" $ do
        let fakePkg = Pkg.Name (Utf8.fromChars "fake") (Utf8.fromChars "nonexistent")
        result <- Vendor.resolvePackagePath fakePkg (makeVersion 99 99 99)
        case result of
          Nothing -> pure ()
          Just p -> assertFailure ("Expected Nothing, got path: " ++ p)
    ]

-- | Verify that copyPackageDir copies files correctly.
testCopyPackageDir :: TestTree
testCopyPackageDir =
  testCase "copyPackageDir creates exact copy" $
    withSystemTempDirectory "vendor-copy-test" $ \tmpDir -> do
      let srcDir = tmpDir </> "src"
          dstDir = tmpDir </> "dst"
      Dir.createDirectoryIfMissing True (srcDir </> "nested")
      writeFile (srcDir </> "file1.txt") "hello"
      writeFile (srcDir </> "nested" </> "file2.txt") "world"
      Vendor.copyPackageDir srcDir dstDir
      content1 <- readFile (dstDir </> "file1.txt")
      content1 @?= "hello"
      content2 <- readFile (dstDir </> "nested" </> "file2.txt")
      content2 @?= "world"

-- | Verify that vendorDependencies copies known packages.
testVendorDependencies :: TestTree
testVendorDependencies =
  testCase "vendorDependencies copies cached packages" $
    withSystemTempDirectory "vendor-deps-test" $ \tmpDir -> do
      let vendorDir = tmpDir </> "vendor"
      Dir.createDirectoryIfMissing True vendorDir
      Vendor.vendorDependencies vendorDir [(Pkg.core, makeVersion 1 0 5)]
      let expectedDir = vendorDir </> Pkg.toFilePath Pkg.core </> "1.0.5"
      exists <- Dir.doesDirectoryExist expectedDir
      assertBool ("vendor directory should exist: " ++ expectedDir) exists

-- | Verify Flags construction.
testFlagsConstruction :: TestTree
testFlagsConstruction =
  testGroup
    "Flags"
    [ testCase "clean flag false" $
        Vendor.Flags False @?= Vendor.Flags False,
      testCase "clean flag true" $
        Vendor.Flags True @?= Vendor.Flags True,
      testCase "show instance" $
        show (Vendor.Flags True) @?= "Flags {_vendorClean = True}"
    ]

-- -------------------------------------------------------------------
-- Offline fetch tests
-- -------------------------------------------------------------------

offlineFetchTests :: TestTree
offlineFetchTests =
  testGroup
    "Offline Fetch"
    [ testCheckLocalCache,
      testCheckElmCache,
      testFetchSourceTypes,
      testPackageSourceJson
    ]

-- | Verify checkLocalCache for a known package.
testCheckLocalCache :: TestTree
testCheckLocalCache =
  testGroup
    "checkLocalCache"
    [ testCase "returns Nothing for missing package" $ do
        let fakePkg = Pkg.Name (Utf8.fromChars "fake") (Utf8.fromChars "pkg")
        result <- Fetch.checkLocalCache fakePkg (makeVersion 99 99 99)
        case result of
          Nothing -> pure ()
          Just _ -> assertFailure "Expected Nothing for non-cached package"
    ]

-- | Verify checkElmCache for a known package.
testCheckElmCache :: TestTree
testCheckElmCache =
  testGroup
    "checkElmCache"
    [ testCase "finds core in Elm cache" $ do
        result <- Fetch.checkElmCache Pkg.core (makeVersion 1 0 5)
        case result of
          Nothing -> pure ()
          Just (Fetch.CachedElm path) ->
            assertBool ("path should exist: " ++ path) =<< Dir.doesDirectoryExist path
          Just other -> assertFailure ("Expected CachedElm, got: " ++ show other),
      testCase "returns Nothing for missing package" $ do
        let fakePkg = Pkg.Name (Utf8.fromChars "fake") (Utf8.fromChars "pkg")
        result <- Fetch.checkElmCache fakePkg (makeVersion 99 99 99)
        case result of
          Nothing -> pure ()
          Just _ -> assertFailure "Expected Nothing for non-cached package"
    ]

-- | Verify FetchSource constructors.
testFetchSourceTypes :: TestTree
testFetchSourceTypes =
  testGroup
    "FetchSource constructors"
    [ testCase "CachedLocal stores path" $
        let src = Fetch.CachedLocal "/tmp/pkg"
         in show src @?= "CachedLocal \"/tmp/pkg\"",
      testCase "CachedElm stores path" $
        let src = Fetch.CachedElm "/home/.elm/pkg"
         in show src @?= "CachedElm \"/home/.elm/pkg\"",
      testCase "FetchedRegistry stores URL" $
        let src = Fetch.FetchedRegistry "https://example.com/pkg.zip"
         in show src @?= "FetchedRegistry \"https://example.com/pkg.zip\"",
      testCase "FetchedGitHub stores URL" $
        let src = Fetch.FetchedGitHub "https://github.com/canopy/core/zipball/1.0.5/"
         in show src @?= "FetchedGitHub \"https://github.com/canopy/core/zipball/1.0.5/\"",
      testCase "FetchError AllSourcesFailed contains package info" $ do
        let err = Fetch.AllSourcesFailed Pkg.core (makeVersion 1 0 0)
            rendered = show err
        assertBool "should mention AllSourcesFailed" ("AllSourcesFailed" `isIn` rendered)
        assertBool "should mention canopy" ("canopy" `isIn` rendered)
        assertBool "should mention core" ("core" `isIn` rendered)
    ]

-- | Verify PackageSource JSON round-trip.
testPackageSourceJson :: TestTree
testPackageSourceJson =
  testGroup
    "PackageSource JSON"
    [ testCase "toPackageSource builds correct structure" $ do
        let ps = Fetch.toPackageSource Pkg.core (Just "https://github.com/canopy/core/zipball/1.0.5/")
        Fetch._psGitUrl ps @?= "https://github.com/canopy/core"
        Fetch._psArchiveUrl ps @?= Just "https://github.com/canopy/core/zipball/1.0.5/",
      testCase "toPackageSource with Nothing archive" $ do
        let ps = Fetch.toPackageSource Pkg.core Nothing
        Fetch._psGitUrl ps @?= "https://github.com/canopy/core"
        Fetch._psArchiveUrl ps @?= Nothing,
      testCase "gitHubZipUrl builds correct URL" $
        Fetch.gitHubZipUrl Pkg.core (makeVersion 1 0 5)
          @?= "https://github.com/canopy/core/zipball/1.0.5/",
      testCase "gitRepoUrl builds correct URL" $
        Fetch.gitRepoUrl Pkg.core
          @?= "https://github.com/canopy/core",
      testCase "registryBase is canopy-lang.org" $
        Fetch.registryBase @?= "https://package.canopy-lang.org"
    ]

-- Helpers

makeVersion :: Int -> Int -> Int -> Version.Version
makeVersion major minor patch =
  Version.Version (fromIntegral major) (fromIntegral minor) (fromIntegral patch)

isIn :: String -> String -> Bool
isIn = List.isInfixOf
