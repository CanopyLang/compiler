{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Compiler.Cache module.
--
-- Tests ELCO header constants, path construction helpers,
-- versioned binary encode/decode roundtrips, and build cache
-- persistence through a temporary directory.
--
-- @since 0.19.1
module Unit.Compiler.CacheTest (tests) where

import qualified Builder.Incremental as Incremental
import qualified Canopy.Data.Name as Name
import qualified Compiler.Cache as Cache
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified System.Directory as Dir
import Data.Word (Word16)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Compiler.Cache Tests"
    [ testElcoConstants,
      testPathConstruction,
      testEncodeDecodeRoundtrip,
      testDecodeVersionedErrors,
      testBuildCacheRoundtrip,
      testLoadMissingBuildCache
    ]

-- ELCO CONSTANTS

testElcoConstants :: TestTree
testElcoConstants =
  testGroup
    "ELCO header constants"
    [ testCase "elcoMagic is 4 bytes spelling ELCO" $
        Cache.elcoMagic @?= LBS.pack [0x45, 0x4C, 0x43, 0x4F],
      testCase "elcoSchemaVersion is 3" $
        Cache.elcoSchemaVersion @?= (3 :: Word16),
      testCase "elcoHeaderSize is 12" $
        Cache.elcoHeaderSize @?= 12,
      testCase "elcoMagic has length 4" $
        LBS.length Cache.elcoMagic @?= 4,
      testCase "encoded header starts with ELCO magic bytes" $
        LBS.take 4 (Cache.encodeVersioned ()) @?= Cache.elcoMagic
    ]

-- PATH CONSTRUCTION

testPathConstruction :: TestTree
testPathConstruction =
  testGroup
    "path construction"
    [ testCase "cachePath appends canopy-stuff/build-cache.json" $
        Cache.cachePath "/project/root" @?= "/project/root/canopy-stuff/build-cache.json",
      testCase "cacheArtifactPath appends canopy-stuff/cache/<name>.elco for Main" $
        Cache.cacheArtifactPath "/project/root" (Name.fromChars "Main")
          @?= "/project/root/canopy-stuff/cache/Main.elco",
      testCase "cacheArtifactPath uses module name as filename" $ do
        let modName = Name.fromChars "App.Utils"
            expected = "/project" </> "canopy-stuff" </> "cache" </> Name.toChars modName ++ ".elco"
        Cache.cacheArtifactPath "/project" modName @?= expected
    ]

-- ENCODE/DECODE ROUNDTRIP

testEncodeDecodeRoundtrip :: TestTree
testEncodeDecodeRoundtrip =
  testGroup
    "encodeVersioned/decodeVersioned roundtrip"
    [ testCase "roundtrip Int value 42" $
        Cache.decodeVersioned (Cache.encodeVersioned (42 :: Int)) @?= Right (42 :: Int),
      testCase "roundtrip Int value 0" $
        Cache.decodeVersioned (Cache.encodeVersioned (0 :: Int)) @?= Right (0 :: Int),
      testCase "roundtrip String value" $
        Cache.decodeVersioned (Cache.encodeVersioned ("hello" :: String)) @?= Right ("hello" :: String),
      testCase "roundtrip empty String" $
        Cache.decodeVersioned (Cache.encodeVersioned ("" :: String)) @?= Right ("" :: String),
      testCase "roundtrip list of Ints" $
        Cache.decodeVersioned (Cache.encodeVersioned ([1, 2, 3] :: [Int])) @?= Right ([1, 2, 3] :: [Int]),
      testCase "roundtrip unit value" $
        Cache.decodeVersioned (Cache.encodeVersioned ()) @?= Right ()
    ]

-- DECODE ERROR CASES

testDecodeVersionedErrors :: TestTree
testDecodeVersionedErrors =
  testGroup
    "decodeVersioned error cases"
    [ testCase "empty bytes returns Left" $
        isLeft (Cache.decodeVersioned LBS.empty :: Either String Int) @?= True,
      testCase "single byte returns Left" $
        isLeft (Cache.decodeVersioned (LBS.singleton 0x45) :: Either String Int) @?= True,
      testCase "truncated 2-byte header returns Left" $
        isLeft (Cache.decodeVersioned (LBS.pack [0x45, 0x4C]) :: Either String Int) @?= True,
      testCase "wrong magic header returns Left" $ do
        let wrongMagic = LBS.pack [0x00, 0x00, 0x00, 0x00] <> LBS.replicate 8 0x00
        isLeft (Cache.decodeVersioned wrongMagic :: Either String Int) @?= True,
      testCase "wrong schema version returns Left" $ do
        let badSchema = Cache.elcoMagic <> Binary.encode (0 :: Word16) <> LBS.replicate 10 0x00
        isLeft (Cache.decodeVersioned badSchema :: Either String Int) @?= True,
      testCase "file too short returns Left for 11-byte input" $ do
        let shortBytes = LBS.replicate 11 0x00
        isLeft (Cache.decodeVersioned shortBytes :: Either String Int) @?= True
    ]

-- BUILD CACHE ROUNDTRIP

testBuildCacheRoundtrip :: TestTree
testBuildCacheRoundtrip =
  testGroup
    "loadBuildCache/saveBuildCache roundtrip"
    [ testCase "save then load produces cache with same entry count" $
        withSystemTempDirectory "cache-test" $ \tmpDir -> do
          initial <- Cache.loadBuildCache tmpDir
          Cache.saveBuildCache tmpDir initial
          reloaded <- Cache.loadBuildCache tmpDir
          Map.size (Incremental.cacheEntries reloaded) @?= Map.size (Incremental.cacheEntries initial),
      testCase "save then load produces cache with same version string" $
        withSystemTempDirectory "cache-test" $ \tmpDir -> do
          initial <- Cache.loadBuildCache tmpDir
          Cache.saveBuildCache tmpDir initial
          reloaded <- Cache.loadBuildCache tmpDir
          Incremental.cacheVersion reloaded @?= Incremental.cacheVersion initial,
      testCase "save creates canopy-stuff directory" $
        withSystemTempDirectory "cache-test" $ \tmpDir -> do
          initial <- Cache.loadBuildCache tmpDir
          Cache.saveBuildCache tmpDir initial
          exists <- Dir.doesFileExist (Cache.cachePath tmpDir)
          exists @?= True
    ]

-- MISSING FILE HANDLING

testLoadMissingBuildCache :: TestTree
testLoadMissingBuildCache =
  testCase "loadBuildCache returns empty cache when file is missing" $
    withSystemTempDirectory "cache-test" $ \tmpDir -> do
      cache <- Cache.loadBuildCache tmpDir
      Map.size (Incremental.cacheEntries cache) @?= 0

-- HELPERS

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False
