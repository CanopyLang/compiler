
-- | Tests for transitive cache invalidation.
--
-- Validates that:
--
-- * When a leaf module's FFI changes, its dependents are invalidated
--   via changed depsHash propagation
-- * Diamond dependencies propagate invalidation correctly
-- * Unrelated modules are not affected by changes in other subgraphs
-- * Inserting the same module name overwrites the previous entry
--
-- @since 0.19.3
module Unit.Builder.CacheInvalidationTest (tests) where

import qualified Builder.Hash as Hash
import qualified Builder.Incremental as Incremental
import qualified Canopy.Data.Name as Name
import Data.Time.Clock (UTCTime, getCurrentTime)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Builder.CacheInvalidation"
    [ testTransitiveInvalidation,
      testCachePruning
    ]

-- HELPERS

mkName :: String -> Name.Name
mkName = Name.fromChars

-- | Build a 'CacheEntry' from seed strings for source, deps, and FFI hashes.
mkEntry :: UTCTime -> String -> String -> String -> Incremental.CacheEntry
mkEntry now srcSeed depsSeed ffiSeed =
  Incremental.CacheEntry
    { Incremental.cacheSourceHash = Hash.hashString srcSeed,
      Incremental.cacheDepsHash = Hash.hashString depsSeed,
      Incremental.cacheArtifactPath = srcSeed ++ ".elco",
      Incremental.cacheTimestamp = now,
      Incremental.cacheInterfaceHash = Nothing,
      Incremental.cacheFFIHash = Hash.hashString ffiSeed
    }

-- | Insert a named entry into the cache.
insertNamed ::
  Incremental.BuildCache ->
  UTCTime ->
  String ->
  String ->
  String ->
  String ->
  Incremental.BuildCache
insertNamed cache now modName srcSeed depsSeed ffiSeed =
  Incremental.insertCache cache (mkName modName) (mkEntry now srcSeed depsSeed ffiSeed)

-- | Assert that a module needs recompile given the supplied hashes.
assertNeedsRecompile ::
  Incremental.BuildCache -> String -> String -> String -> String -> IO ()
assertNeedsRecompile cache modName srcSeed depsSeed ffiSeed =
  Incremental.needsRecompile cache (mkName modName) src deps ffi
    @?= True
  where
    src = Hash.hashString srcSeed
    deps = Hash.hashString depsSeed
    ffi = Hash.hashString ffiSeed

-- | Assert that a module does NOT need recompile given the supplied hashes.
assertNoRecompile ::
  Incremental.BuildCache -> String -> String -> String -> String -> IO ()
assertNoRecompile cache modName srcSeed depsSeed ffiSeed =
  Incremental.needsRecompile cache (mkName modName) src deps ffi
    @?= False
  where
    src = Hash.hashString srcSeed
    deps = Hash.hashString depsSeed
    ffi = Hash.hashString ffiSeed

-- TRANSITIVE INVALIDATION

testTransitiveInvalidation :: TestTree
testTransitiveInvalidation =
  testGroup
    "transitive invalidation"
    [ testCase "FFI change in leaf module invalidates dependents via depsHash" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let original = buildLinearChain cache now
        assertNoRecompile original "A" "srcA" "depsA" "ffiA"
        assertNoRecompile original "B" "srcB" "depsB" "ffiB"
        assertNoRecompile original "C" "srcC" "depsC" "ffiC"
        assertNeedsRecompile original "C" "srcC" "depsC" "ffiC-changed"
        assertNeedsRecompile original "B" "srcB" "depsB-changed" "ffiB"
        assertNeedsRecompile original "A" "srcA" "depsA-changed" "ffiA",
      testCase "diamond dependency propagates correctly" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let diamond = buildDiamond cache now
        assertNoRecompile diamond "A" "srcA" "depsA" "ffiA"
        assertNoRecompile diamond "B" "srcB" "depsB" "ffiB"
        assertNoRecompile diamond "C" "srcC" "depsC" "ffiC"
        assertNoRecompile diamond "D" "srcD" "depsD" "ffiD"
        assertNeedsRecompile diamond "D" "srcD" "depsD" "ffiD-changed"
        assertNeedsRecompile diamond "B" "srcB" "depsB-changed" "ffiB"
        assertNeedsRecompile diamond "C" "srcC" "depsC-changed" "ffiC"
        assertNeedsRecompile diamond "A" "srcA" "depsA-changed" "ffiA",
      testCase "unrelated module is not affected" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let graph = buildWithUnrelated cache now
        assertNeedsRecompile graph "B" "srcB" "depsB" "ffiB-changed"
        assertNeedsRecompile graph "A" "srcA" "depsA-changed" "ffiA"
        assertNoRecompile graph "C" "srcC" "depsC" "ffiC"
    ]

-- | A -> B -> C (linear chain). C has FFI.
buildLinearChain :: Incremental.BuildCache -> UTCTime -> Incremental.BuildCache
buildLinearChain cache now =
  insertNamed
    (insertNamed
      (insertNamed cache now "C" "srcC" "depsC" "ffiC")
      now "B" "srcB" "depsB" "ffiB")
    now "A" "srcA" "depsA" "ffiA"

-- | Diamond: A -> B, A -> C, B -> D, C -> D. D is leaf with FFI.
buildDiamond :: Incremental.BuildCache -> UTCTime -> Incremental.BuildCache
buildDiamond cache now =
  insertNamed
    (insertNamed
      (insertNamed
        (insertNamed cache now "D" "srcD" "depsD" "ffiD")
        now "C" "srcC" "depsC" "ffiC")
      now "B" "srcB" "depsB" "ffiB")
    now "A" "srcA" "depsA" "ffiA"

-- | A -> B (B has FFI), C is independent.
buildWithUnrelated :: Incremental.BuildCache -> UTCTime -> Incremental.BuildCache
buildWithUnrelated cache now =
  insertNamed
    (insertNamed
      (insertNamed cache now "B" "srcB" "depsB" "ffiB")
      now "A" "srcA" "depsA" "ffiA")
    now "C" "srcC" "depsC" "ffiC"

-- CACHE PRUNING

testCachePruning :: TestTree
testCachePruning =
  testGroup
    "cache pruning"
    [ testCase "inserting same module name overwrites old entry" $ do
        cache <- Incremental.emptyCache
        now <- getCurrentTime
        let cache' = insertNamed cache now "Main" "src1" "deps1" "ffi1"
            cache'' = insertNamed cache' now "Main" "src2" "deps2" "ffi2"
        assertNoRecompile cache'' "Main" "src2" "deps2" "ffi2"
        assertNeedsRecompile cache'' "Main" "src1" "deps1" "ffi1"
    ]
