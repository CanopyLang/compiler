
-- | Unit tests for Builder.Incremental module.
--
-- Tests incremental compilation cache including change detection,
-- cache persistence, and invalidation.
--
-- @since 0.19.1
module Unit.Builder.IncrementalTest (tests) where

import qualified Builder.Hash as Hash
import qualified Builder.Incremental as Incremental
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import qualified System.IO
import System.IO (Handle)
import System.IO.Temp (withSystemTempFile)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Builder.Incremental Tests"
    [ testEmptyCache,
      testCacheOperations,
      testChangeDetection,
      testCachePersistence,
      testInvalidation,
      testPruning,
      testInterfaceHashing,
      testLargeCache,
      testPruningEdgeCases,
      testInterfaceHashPropagation,
      testEmptyCacheOperations
    ]

-- Helper to create test module names
mkName :: String -> Name.Name
mkName = Name.fromChars

testEmptyCache :: TestTree
testEmptyCache =
  testGroup
    "empty cache tests"
    [ testCase "empty cache has no entries" $ do
        cache <- Incremental.emptyCache
        Map.size (Incremental.cacheEntries cache) @?= 0,
      testCase "empty cache has correct version" $ do
        cache <- Incremental.emptyCache
        Incremental.cacheVersion cache @?= "0.19.1",
      testCase "lookup in empty cache returns Nothing" $ do
        cache <- Incremental.emptyCache
        Incremental.lookupCache cache (mkName "Main") @?= Nothing
    ]

testCacheOperations :: TestTree
testCacheOperations =
  testGroup
    "cache operation tests"
    [ testCase "insert and lookup entry" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let hash1 = Hash.hashString "source"
        let hash2 = Hash.hashString "deps"
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = hash1,
                  Incremental.cacheDepsHash = hash2,
                  Incremental.cacheArtifactPath = "path/to/artifact",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Main") entry
        case Incremental.lookupCache cache' (mkName "Main") of
          Nothing -> assertFailure "Expected cache entry"
          Just found -> do
            Incremental.cacheSourceHash found @?= hash1
            Incremental.cacheDepsHash found @?= hash2
            Incremental.cacheArtifactPath found @?= "path/to/artifact",
      testCase "insert multiple entries" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let entry1 =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s1",
                  Incremental.cacheDepsHash = Hash.hashString "d1",
                  Incremental.cacheArtifactPath = "path1",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let entry2 =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s2",
                  Incremental.cacheDepsHash = Hash.hashString "d2",
                  Incremental.cacheArtifactPath = "path2",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' =
              Incremental.insertCache
                (Incremental.insertCache cache (mkName "Main") entry1)
                (mkName "Utils")
                entry2
        Map.size (Incremental.cacheEntries cache') @?= 2,
      testCase "insert overwrites existing entry" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let entry1 =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "old",
                  Incremental.cacheDepsHash = Hash.hashString "deps",
                  Incremental.cacheArtifactPath = "old/path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let entry2 =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "new",
                  Incremental.cacheDepsHash = Hash.hashString "deps",
                  Incremental.cacheArtifactPath = "new/path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' =
              Incremental.insertCache
                (Incremental.insertCache cache (mkName "Main") entry1)
                (mkName "Main")
                entry2
        case Incremental.lookupCache cache' (mkName "Main") of
          Nothing -> assertFailure "Expected cache entry"
          Just found ->
            Incremental.cacheArtifactPath found @?= "new/path"
    ]

testChangeDetection :: TestTree
testChangeDetection =
  testGroup
    "change detection tests"
    [ testCase "needs recompile when not in cache" $ do
        cache <- Incremental.emptyCache
        let sourceHash = Hash.hashString "source"
        let depsHash = Hash.hashString "deps"
        Incremental.needsRecompile cache (mkName "Main") sourceHash depsHash Hash.emptyHash
          @?= True,
      testCase "no recompile when hashes match" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let sourceHash = Hash.hashString "source"
        let depsHash = Hash.hashString "deps"
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = sourceHash,
                  Incremental.cacheDepsHash = depsHash,
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Main") entry
        Incremental.needsRecompile cache' (mkName "Main") sourceHash depsHash Hash.emptyHash
          @?= False,
      testCase "needs recompile when source hash changes" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let oldSourceHash = Hash.hashString "old source"
        let newSourceHash = Hash.hashString "new source"
        let depsHash = Hash.hashString "deps"
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = oldSourceHash,
                  Incremental.cacheDepsHash = depsHash,
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Main") entry
        Incremental.needsRecompile cache' (mkName "Main") newSourceHash depsHash Hash.emptyHash
          @?= True,
      testCase "needs recompile when deps hash changes" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let sourceHash = Hash.hashString "source"
        let oldDepsHash = Hash.hashString "old deps"
        let newDepsHash = Hash.hashString "new deps"
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = sourceHash,
                  Incremental.cacheDepsHash = oldDepsHash,
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Main") entry
        Incremental.needsRecompile cache' (mkName "Main") sourceHash newDepsHash Hash.emptyHash
          @?= True
    ]

testCachePersistence :: TestTree
testCachePersistence =
  testGroup
    "cache persistence tests"
    [ testCase "save and load empty cache" $
        withSystemTempFile "cache.json" $ \path handle -> do
          hClose handle
          cache <- Incremental.emptyCache
          Incremental.saveCache path cache
          loaded <- Incremental.loadCache path
          case loaded of
            Nothing -> assertFailure "Failed to load cache"
            Just loadedCache ->
              Map.size (Incremental.cacheEntries loadedCache) @?= 0,
      testCase "save and load cache with entries" $
        withSystemTempFile "cache.json" $ \path handle -> do
          hClose handle
          cache <- Incremental.emptyCache
          now <- getCurrentTime
          let entry =
                Incremental.CacheEntry
                  { Incremental.cacheSourceHash = Hash.hashString "source",
                    Incremental.cacheDepsHash = Hash.hashString "deps",
                    Incremental.cacheArtifactPath = "artifact/path",
                    Incremental.cacheTimestamp = now,
                    Incremental.cacheInterfaceHash = Nothing,
                    Incremental.cacheFFIHash = Hash.emptyHash
                  }
          let cache' = Incremental.insertCache cache (mkName "Main") entry
          Incremental.saveCache path cache'
          loaded <- Incremental.loadCache path
          case loaded of
            Nothing -> assertFailure "Failed to load cache"
            Just loadedCache -> do
              Map.size (Incremental.cacheEntries loadedCache) @?= 1
              case Incremental.lookupCache loadedCache (mkName "Main") of
                Nothing -> assertFailure "Expected Main entry"
                Just loadedEntry ->
                  Incremental.cacheArtifactPath loadedEntry @?= "artifact/path",
      testCase "load non-existent cache returns Nothing" $ do
        loaded <- Incremental.loadCache "/nonexistent/cache.json"
        loaded @?= Nothing
    ]

testInvalidation :: TestTree
testInvalidation =
  testGroup
    "invalidation tests"
    [ testCase "invalidate single module" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Main") entry
        let cache'' = Incremental.invalidateModule cache' (mkName "Main")
        Incremental.lookupCache cache'' (mkName "Main") @?= Nothing,
      testCase "invalidate non-existent module" $ do
        cache <- Incremental.emptyCache
        let cache' = Incremental.invalidateModule cache (mkName "NotFound")
        Map.size (Incremental.cacheEntries cache') @?= 0,
      testCase "invalidate transitive dependencies" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' =
              Incremental.insertCache
                (Incremental.insertCache cache (mkName "Main") entry)
                (mkName "Utils")
                entry
        -- Main depends on Utils: Utils -> [Main]
        let reverseDeps = Map.singleton (mkName "Utils") [mkName "Main"]
        let cache'' = Incremental.invalidateTransitive cache' (mkName "Utils") reverseDeps
        -- Both Utils and Main should be invalidated
        Incremental.lookupCache cache'' (mkName "Utils") @?= Nothing
        Incremental.lookupCache cache'' (mkName "Main") @?= Nothing,
      testCase "invalidate transitive chain" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' =
              Incremental.insertCache
                ( Incremental.insertCache
                    (Incremental.insertCache cache (mkName "Base") entry)
                    (mkName "Utils")
                    entry
                )
                (mkName "Main")
                entry
        -- Base -> Utils -> Main
        let reverseDeps =
              Map.fromList
                [ (mkName "Base", [mkName "Utils"]),
                  (mkName "Utils", [mkName "Main"])
                ]
        let cache'' = Incremental.invalidateTransitive cache' (mkName "Base") reverseDeps
        -- All three should be invalidated
        Incremental.lookupCache cache'' (mkName "Base") @?= Nothing
        Incremental.lookupCache cache'' (mkName "Utils") @?= Nothing
        Incremental.lookupCache cache'' (mkName "Main") @?= Nothing
    ]

testPruning :: TestTree
testPruning =
  testGroup
    "cache pruning tests"
    [ testCase "prune old entries" $ do
        now <- getCurrentTime
        let oldTime = addUTCTime (-7200) now -- 2 hours ago
        let recentTime = addUTCTime (-1800) now -- 30 minutes ago
        cache <- Incremental.emptyCache
        let oldEntry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "old/path",
                  Incremental.cacheTimestamp = oldTime,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let recentEntry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "recent/path",
                  Incremental.cacheTimestamp = recentTime,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' =
              Incremental.insertCache
                (Incremental.insertCache cache (mkName "Old") oldEntry)
                (mkName "Recent")
                recentEntry
        let cutoffTime = addUTCTime (-3600) now -- 1 hour ago
        let cache'' = Incremental.pruneCache cache' cutoffTime
        -- Old entry should be pruned, recent should remain
        Map.size (Incremental.cacheEntries cache'') @?= 1
        Incremental.lookupCache cache'' (mkName "Recent") /= Nothing @? "Recent entry should exist",
      testCase "prune with no old entries" $ do
        now <- getCurrentTime
        cache <- Incremental.emptyCache
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Main") entry
        let cutoffTime = addUTCTime (-3600) now -- 1 hour ago
        let cache'' = Incremental.pruneCache cache' cutoffTime
        Map.size (Incremental.cacheEntries cache'') @?= 1
    ]

testInterfaceHashing :: TestTree
testInterfaceHashing =
  testGroup
    "interface hash tests"
    [ testCase "getInterfaceHash returns Nothing for missing module" $ do
        cache <- Incremental.emptyCache
        Incremental.getInterfaceHash cache (mkName "Main") @?= Nothing,
      testCase "getInterfaceHash returns Nothing when hash not stored" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Main") entry
        Incremental.getInterfaceHash cache' (mkName "Main") @?= Nothing,
      testCase "getInterfaceHash returns stored hash" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let ifaceHash = Hash.hashString "interface-content"
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Just ifaceHash,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Main") entry
        case Incremental.getInterfaceHash cache' (mkName "Main") of
          Nothing -> assertFailure "Expected interface hash"
          Just h -> Hash.hashesEqual h ifaceHash @?= True,
      testCase "interfaceUnchanged returns True for matching hash" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let ifaceHash = Hash.hashString "interface-content"
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Just ifaceHash,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Main") entry
        Incremental.interfaceUnchanged cache' (mkName "Main") ifaceHash @?= True,
      testCase "interfaceUnchanged returns False for different hash" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let oldIfaceHash = Hash.hashString "old-interface"
        let newIfaceHash = Hash.hashString "new-interface"
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Just oldIfaceHash,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Main") entry
        Incremental.interfaceUnchanged cache' (mkName "Main") newIfaceHash @?= False,
      testCase "interfaceUnchanged returns False for missing module" $ do
        cache <- Incremental.emptyCache
        let ifaceHash = Hash.hashString "interface-content"
        Incremental.interfaceUnchanged cache (mkName "Main") ifaceHash @?= False,
      testCase "interface hash roundtrips through JSON" $
        withSystemTempFile "cache.json" $ \path handle -> do
          hClose handle
          cache <- Incremental.emptyCache
          now <- getCurrentTime
          let ifaceHash = Hash.hashString "interface-data"
          let entry =
                Incremental.CacheEntry
                  { Incremental.cacheSourceHash = Hash.hashString "s",
                    Incremental.cacheDepsHash = Hash.hashString "d",
                    Incremental.cacheArtifactPath = "path",
                    Incremental.cacheTimestamp = now,
                    Incremental.cacheInterfaceHash = Just ifaceHash,
                    Incremental.cacheFFIHash = Hash.emptyHash
                  }
          let cache' = Incremental.insertCache cache (mkName "Main") entry
          Incremental.saveCache path cache'
          loaded <- Incremental.loadCache path
          case loaded of
            Nothing -> assertFailure "Failed to load cache"
            Just loadedCache ->
              case Incremental.getInterfaceHash loadedCache (mkName "Main") of
                Nothing -> assertFailure "Expected interface hash after load"
                Just loadedHash ->
                  Hash.hashesEqual loadedHash ifaceHash @?= True
    ]

testLargeCache :: TestTree
testLargeCache =
  testGroup
    "large cache tests"
    [ testCase "cache with 10 entries stores all entries" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let names = map (\i -> mkName ("Module" ++ show i)) [1 :: Int .. 10]
        let cache' = foldr (insertEntry now) cache names
        Map.size (Incremental.cacheEntries cache') @?= 10,
      testCase "all 10 entries are retrievable after insertion" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let names = map (\i -> mkName ("Module" ++ show i)) [1 :: Int .. 10]
        let cache' = foldr (insertEntry now) cache names
        let missing = filter (\n -> Incremental.lookupCache cache' n == Nothing) names
        missing @?= [],
      testCase "12 entries can be saved and reloaded" $
        withSystemTempFile "large-cache.json" $ \path handle -> do
          hClose handle
          cache <- Incremental.emptyCache
          now <- getCurrentTime
          let names = map (\i -> mkName ("M" ++ show i)) [1 :: Int .. 12]
          let cache' = foldr (insertEntry now) cache names
          Incremental.saveCache path cache'
          loaded <- Incremental.loadCache path
          case loaded of
            Nothing -> assertFailure "Failed to load large cache"
            Just loadedCache ->
              Map.size (Incremental.cacheEntries loadedCache) @?= 12
    ]

-- | Insert a simple cache entry for a named module.
insertEntry :: UTCTime -> Name.Name -> Incremental.BuildCache -> Incremental.BuildCache
insertEntry now name cache =
  Incremental.insertCache cache name entry
  where
    entry =
      Incremental.CacheEntry
        { Incremental.cacheSourceHash = Hash.hashString (show name),
          Incremental.cacheDepsHash = Hash.hashString "deps",
          Incremental.cacheArtifactPath = "path/" ++ show name,
          Incremental.cacheTimestamp = now,
          Incremental.cacheInterfaceHash = Nothing,
          Incremental.cacheFFIHash = Hash.emptyHash
        }

testPruningEdgeCases :: TestTree
testPruningEdgeCases =
  testGroup
    "pruning edge case tests"
    [ testCase "pruning empty cache returns empty cache" $ do
        now <- getCurrentTime
        cache <- Incremental.emptyCache
        let cutoff = addUTCTime (-3600) now
        let cache' = Incremental.pruneCache cache cutoff
        Map.size (Incremental.cacheEntries cache') @?= 0,
      testCase "prune with future cutoff removes all entries" $ do
        now <- getCurrentTime
        cache <- Incremental.emptyCache
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = addUTCTime (-7200) now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Old") entry
        let futureTime = addUTCTime 3600 now
        let cache'' = Incremental.pruneCache cache' futureTime
        Map.size (Incremental.cacheEntries cache'') @?= 0,
      testCase "prune keeps entries exactly at cutoff boundary" $ do
        now <- getCurrentTime
        cache <- Incremental.emptyCache
        let cutoff = addUTCTime (-3600) now
        let entry =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = addUTCTime (-1800) now,
                  Incremental.cacheInterfaceHash = Nothing,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "Fresh") entry
        let cache'' = Incremental.pruneCache cache' cutoff
        Map.size (Incremental.cacheEntries cache'') @?= 1
    ]

testInterfaceHashPropagation :: TestTree
testInterfaceHashPropagation =
  testGroup
    "interface hash propagation tests"
    [ testCase "inserting updated entry with new interface hash is reflected" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let oldHash = Hash.hashString "old-iface"
        let newHash = Hash.hashString "new-iface"
        let mkEntry ifaceHash =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Just ifaceHash,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "M") (mkEntry oldHash)
        let cache'' = Incremental.insertCache cache' (mkName "M") (mkEntry newHash)
        Incremental.interfaceUnchanged cache'' (mkName "M") newHash @?= True,
      testCase "interfaceUnchanged is False after replacing hash" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let h1 = Hash.hashString "iface-v1"
        let h2 = Hash.hashString "iface-v2"
        let mkEntry h =
              Incremental.CacheEntry
                { Incremental.cacheSourceHash = Hash.hashString "s",
                  Incremental.cacheDepsHash = Hash.hashString "d",
                  Incremental.cacheArtifactPath = "path",
                  Incremental.cacheTimestamp = now,
                  Incremental.cacheInterfaceHash = Just h,
                  Incremental.cacheFFIHash = Hash.emptyHash
                }
        let cache' = Incremental.insertCache cache (mkName "M") (mkEntry h1)
        let cache'' = Incremental.insertCache cache' (mkName "M") (mkEntry h2)
        Incremental.interfaceUnchanged cache'' (mkName "M") h1 @?= False
    ]

testEmptyCacheOperations :: TestTree
testEmptyCacheOperations =
  testGroup
    "empty cache operation tests"
    [ testCase "invalidating from empty cache is a no-op" $ do
        cache <- Incremental.emptyCache
        let cache' = Incremental.invalidateModule cache (mkName "Ghost")
        Map.size (Incremental.cacheEntries cache') @?= 0,
      testCase "invalidateTransitive on empty cache with empty revDeps is a no-op" $ do
        cache <- Incremental.emptyCache
        let cache' = Incremental.invalidateTransitive cache (mkName "Ghost") Map.empty
        Map.size (Incremental.cacheEntries cache') @?= 0,
      testCase "getInterfaceHash on empty cache returns Nothing" $ do
        cache <- Incremental.emptyCache
        Incremental.getInterfaceHash cache (mkName "Missing") @?= Nothing,
      testCase "needsRecompile on empty cache always returns True" $ do
        cache <- Incremental.emptyCache
        let sh = Hash.hashString "src"
        let dh = Hash.hashString "deps"
        Incremental.needsRecompile cache (mkName "Any") sh dh Hash.emptyHash @?= True
    ]

hClose :: Handle -> IO ()
hClose = System.IO.hClose
