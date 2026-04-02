
-- | Tests for FFI-aware cache invalidation.
--
-- Validates that:
--
-- * 'computeFFIHash' produces stable, content-sensitive hashes
-- * 'needsRecompile' detects FFI file changes independently of source\/deps
-- * 'CacheEntry' round-trips through the binary format preserving 'cacheFFIHash'
-- * Package-level 'ArtifactCache' FFI fingerprints detect stale JS files
--
-- @since 0.19.3
module Unit.Builder.FFICacheTest (tests) where

import qualified AST.Optimized as Opt
import qualified Builder.Hash as Hash
import qualified Builder.Incremental as Incremental
import qualified Compiler.Cache as Cache
import qualified Data.Binary as Binary
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Canopy.Data.Name as Name
import Data.Time.Clock (getCurrentTime)
import qualified PackageCache
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.IO
import System.IO (Handle)
import System.IO.Temp (withSystemTempDirectory, withSystemTempFile)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Builder.FFICache"
    [ testComputeFFIHash,
      testModuleCacheFFIInvalidation,
      testCacheEntryRoundTrip,
      testArtifactFFIFingerprints
    ]

-- HELPERS

mkName :: String -> Name.Name
mkName = Name.fromChars

hClose :: Handle -> IO ()
hClose = System.IO.hClose

-- | Write a file with the given contents into a subdirectory of the root.
writeFFIFile :: FilePath -> FilePath -> String -> IO ()
writeFFIFile root relPath content = do
  let absPath = root </> relPath
  Dir.createDirectoryIfMissing True (root </> "external")
  writeFile absPath content

-- | An empty 'PackageCache.Artifacts' suitable for constructing test
-- 'PackageCache.ArtifactCache' values where the artifacts field is not
-- under test.  All maps are empty.
emptyArtifacts :: PackageCache.Artifacts
emptyArtifacts =
  PackageCache.Artifacts Map.empty (Opt.GlobalGraph Map.empty Map.empty Map.empty) Map.empty

-- FFI HASH COMPUTATION

testComputeFFIHash :: TestTree
testComputeFFIHash =
  testGroup
    "computeFFIHash"
    [ testCase "empty path list returns emptyHash" $ do
        h <- Cache.computeFFIHash "/nonexistent" []
        Hash.hashesEqual h Hash.emptyHash @? "empty path list should produce emptyHash",
      testCase "same content produces same hash" $
        withSystemTempDirectory "ffi-hash" $ \root -> do
          writeFFIFile root "external/a.js" "console.log('hello');"
          h1 <- Cache.computeFFIHash root ["external/a.js"]
          h2 <- Cache.computeFFIHash root ["external/a.js"]
          Hash.hashesEqual h1 h2 @? "same file should produce same hash",
      testCase "different content produces different hash" $
        withSystemTempDirectory "ffi-hash" $ \root -> do
          writeFFIFile root "external/a.js" "version1"
          h1 <- Cache.computeFFIHash root ["external/a.js"]
          writeFFIFile root "external/a.js" "version2"
          h2 <- Cache.computeFFIHash root ["external/a.js"]
          Hash.hashChanged h1 h2 @? "different content should produce different hash",
      testCase "missing file does not crash" $
        withSystemTempDirectory "ffi-hash" $ \root -> do
          _ <- Cache.computeFFIHash root ["external/missing.js"]
          assertBool "computeFFIHash should handle missing files gracefully" True,
      testCase "order of paths is deterministic (sorted internally)" $
        withSystemTempDirectory "ffi-hash" $ \root -> do
          writeFFIFile root "external/a.js" "aaa"
          writeFFIFile root "external/b.js" "bbb"
          h1 <- Cache.computeFFIHash root ["external/a.js", "external/b.js"]
          h2 <- Cache.computeFFIHash root ["external/b.js", "external/a.js"]
          Hash.hashesEqual h1 h2 @? "path order should not affect hash (sorted internally)"
    ]

-- MODULE CACHE FFI INVALIDATION

testModuleCacheFFIInvalidation :: TestTree
testModuleCacheFFIInvalidation =
  testGroup
    "needsRecompile with FFI hash"
    [ testCase "returns False when all three hashes match" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let srcH = Hash.hashString "source"
            depsH = Hash.hashString "deps"
            ffiH = Hash.hashString "ffi-content"
            entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = srcH,
                  Incremental.cacheDepsHash = depsH,
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = ffiH
                }
            cache' = Incremental.insertCache cache (mkName "Main") entry
        Incremental.needsRecompile cache' (mkName "Main") srcH depsH ffiH
          @?= False,
      testCase "returns True when only FFI hash changes" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let srcH = Hash.hashString "source"
            depsH = Hash.hashString "deps"
            oldFFI = Hash.hashString "old-ffi"
            newFFI = Hash.hashString "new-ffi"
            entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = srcH,
                  Incremental.cacheDepsHash = depsH,
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = oldFFI
                }
            cache' = Incremental.insertCache cache (mkName "Main") entry
        Incremental.needsRecompile cache' (mkName "Main") srcH depsH newFFI
          @?= True,
      testCase "returns True when FFI goes from empty to non-empty" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let srcH = Hash.hashString "source"
            depsH = Hash.hashString "deps"
            entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = srcH,
                  Incremental.cacheDepsHash = depsH,
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
            cache' = Incremental.insertCache cache (mkName "Main") entry
            newFFI = Hash.hashString "new-ffi-content"
        Incremental.needsRecompile cache' (mkName "Main") srcH depsH newFFI
          @?= True
    ]

-- BINARY ROUND-TRIP

testCacheEntryRoundTrip :: TestTree
testCacheEntryRoundTrip =
  testGroup
    "CacheEntry binary round-trip preserves cacheFFIHash"
    [ testCase "round-trip with non-empty FFI hash" $ do
        now <- getCurrentTime
        let ffiH = Hash.hashString "ffi-file-content"
            entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "src",
                  Incremental.cacheDepsHash = Hash.hashString "deps",
                  Incremental.cacheArtifactPath = "artifact.elco",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Just (Hash.hashString "iface"),
                  Incremental.cacheFFIHash = ffiH
                }
            decoded = Binary.decode (Binary.encode entry) :: Incremental.CacheEntry
        Hash.hashesEqual (Incremental.cacheFFIHash decoded) ffiH
          @? "FFI hash should survive binary round-trip",
      testCase "round-trip with emptyHash FFI" $ do
        now <- getCurrentTime
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "src",
                  Incremental.cacheDepsHash = Hash.hashString "deps",
                  Incremental.cacheArtifactPath = "artifact.elco",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
            decoded = Binary.decode (Binary.encode entry) :: Incremental.CacheEntry
        Hash.hashesEqual (Incremental.cacheFFIHash decoded) Hash.emptyHash
          @? "emptyHash FFI should survive binary round-trip",
      testCase "full BuildCache round-trip preserves FFI hash" $
        withSystemTempFile "cache.bin" $ \path handle -> do
          hClose handle
          now <- getCurrentTime
          let ffiH = Hash.hashString "external/widget.js content"
              entry =
                Incremental.CacheEntry
                  { Incremental.cacheSourceHash = Hash.hashString "src",
                    Incremental.cacheDepsHash = Hash.hashString "deps",
                    Incremental.cacheArtifactPath = "artifact.elco",
                    Incremental.cacheTimestamp = now,
                    Incremental.cacheInterfaceHash = Nothing,
                    Incremental.cacheFFIHash = ffiH
                  }
          cache <- Incremental.emptyCache
          let cache' = Incremental.insertCache cache (mkName "Widget") entry
          Incremental.saveCache path cache'
          loaded <- Incremental.loadCache path
          case loaded of
            Nothing -> assertFailure "Failed to reload BuildCache"
            Just loadedCache ->
              case Incremental.lookupCache loadedCache (mkName "Widget") of
                Nothing -> assertFailure "Widget entry missing after reload"
                Just loadedEntry ->
                  Hash.hashesEqual (Incremental.cacheFFIHash loadedEntry) ffiH
                    @? "FFI hash should survive BuildCache save/load cycle"
    ]

-- ARTIFACT FFI FINGERPRINTS

testArtifactFFIFingerprints :: TestTree
testArtifactFFIFingerprints =
  testGroup
    "ArtifactCache FFI fingerprints"
    [ testCase "verifyFFIFingerprints detects changed file" $
        withSystemTempDirectory "ffi-fp" $ \root -> do
          writeFile (root </> "widget.js") "// original"
          originalBytes <- BSC.readFile (root </> "widget.js")
          let originalHash = Hash.hashBytes originalBytes
              fingerprints = Map.singleton "widget.js" originalHash
              cache = PackageCache.ArtifactCache
                { PackageCache._fingerprints = Set.empty
                , PackageCache._artifacts = emptyArtifacts
                , PackageCache._ffiFingerprints = fingerprints
                }
          -- Fingerprints should match with original content
          valid1 <- PackageCache.verifyFFIFingerprints root cache
          valid1 @? "fingerprints should match with unchanged file"
          -- Modify the file
          writeFile (root </> "widget.js") "// modified"
          valid2 <- PackageCache.verifyFFIFingerprints root cache
          not valid2 @? "fingerprints should NOT match after file modification",
      testCase "verifyFFIFingerprints detects deleted file" $
        withSystemTempDirectory "ffi-fp" $ \root -> do
          writeFile (root </> "temp.js") "content"
          bytes <- BSC.readFile (root </> "temp.js")
          let fingerprints = Map.singleton "temp.js" (Hash.hashBytes bytes)
              cache = PackageCache.ArtifactCache
                { PackageCache._fingerprints = Set.empty
                , PackageCache._artifacts = emptyArtifacts
                , PackageCache._ffiFingerprints = fingerprints
                }
          Dir.removeFile (root </> "temp.js")
          valid <- PackageCache.verifyFFIFingerprints root cache
          not valid @? "fingerprints should NOT match when file is deleted",
      testCase "verifyFFIFingerprints passes with empty fingerprints" $ do
          let cache = PackageCache.ArtifactCache
                { PackageCache._fingerprints = Set.empty
                , PackageCache._artifacts = emptyArtifacts
                , PackageCache._ffiFingerprints = Map.empty
                }
          valid <- PackageCache.verifyFFIFingerprints "/nonexistent" cache
          valid @? "empty fingerprints should always pass"
    ]
