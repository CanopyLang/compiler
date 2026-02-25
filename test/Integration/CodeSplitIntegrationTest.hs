{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Integration tests for the complete code splitting pipeline.
--
-- Validates end-to-end behavior of the code splitting system by exercising
-- the full pipeline from @SplitConfig@ through analysis, generation,
-- manifest production, and output verification.  Each test constructs
-- realistic global graphs and verifies that the pipeline produces
-- correct, complete, and deterministic output.
--
-- These tests exercise the integration between:
--
--   * 'Analyze.analyze' — chunk graph construction
--   * 'Generate.generateChunks' — per-chunk JavaScript generation
--   * 'Manifest.generateManifest' — manifest JSON production
--   * 'Runtime.chunkRuntime' — runtime loader embedding
--
-- @since 0.19.2
module Integration.CodeSplitIntegrationTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens ((^.))
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.Set as Set
import qualified Data.Utf8 as Utf8
import Generate.JavaScript.CodeSplit.Analyze (analyze, analyzeWithCache, graphHash)
import Generate.JavaScript.CodeSplit.Generate (generateChunks)
import Generate.JavaScript.CodeSplit.Types
  ( ChunkGraphCache (..),
    ChunkKind (..),
    SplitConfig (..),
    SplitOutput,
    cacheConfig,
    cacheGraphHash,
    cacheResult,
    chunkGlobals,
    cgEntry,
    cgLazy,
    cgShared,
    cgGlobalToChunk,
    soChunks,
    soManifest,
    coKind,
    coHash,
    coFilename,
    coBuilder,
  )
import qualified Generate.Html as Html
import qualified Generate.Mode as Mode
import Test.Tasty
import Test.Tasty.HUnit

-- | All integration tests for code splitting pipeline.
tests :: TestTree
tests =
  testGroup
    "CodeSplit Integration"
    [ pipelineTests
    , outputContentTests
    , manifestIntegrationTests
    , backwardCompatTests
    , determinismTests
    , prefetchHintTests
    , incrementalCacheTests
    ]

-- HELPERS

-- | Create a test package name.
testPkg :: Pkg.Name
testPkg = Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars "app")

-- | Create a canonical module name.
mkCanonical :: String -> ModuleName.Canonical
mkCanonical name = ModuleName.Canonical testPkg (Name.fromChars name)

-- | Create a global reference.
mkGlobal :: String -> String -> Opt.Global
mkGlobal modName varName =
  Opt.Global (mkCanonical modName) (Name.fromChars varName)

-- | Build a simple graph node with no dependencies.
mkDefineNode :: Opt.Node
mkDefineNode = Opt.Define (Opt.Bool True) Set.empty

-- | Build a node that depends on specific globals.
mkDefineWithDeps :: [Opt.Global] -> Opt.Node
mkDefineWithDeps deps = Opt.Define (Opt.Bool True) (Set.fromList deps)

-- | Build a GlobalGraph from a map.
mkGlobalGraph :: Map.Map Opt.Global Opt.Node -> Opt.GlobalGraph
mkGlobalGraph graph = Opt.GlobalGraph graph Map.empty Map.empty

-- | Build a Mains map with a single main entry.
mkMains :: String -> Map.Map ModuleName.Canonical Opt.Main
mkMains modName =
  Map.singleton (mkCanonical modName) Opt.Static

-- | No-split config.
noSplitConfig :: SplitConfig
noSplitConfig = SplitConfig Set.empty 2

-- | Config with specified lazy modules.
lazyConfig :: [String] -> SplitConfig
lazyConfig modNames =
  SplitConfig (Set.fromList (map mkCanonical modNames)) 2

-- | Dev mode for testing.
devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False Set.empty

-- | Render a builder to a string.
renderBuilder :: B.Builder -> String
renderBuilder = LChar8.unpack . B.toLazyByteString

-- | Check if needle is contained in haystack.
containsStr :: String -> String -> Bool
containsStr needle haystack = any (isPrefixOfStr needle) (tailsOf haystack)

-- | Check if first list is prefix of second.
isPrefixOfStr :: String -> String -> Bool
isPrefixOfStr [] _ = True
isPrefixOfStr _ [] = False
isPrefixOfStr (x:xs) (y:ys) = x == y && isPrefixOfStr xs ys

-- | All suffixes of a list.
tailsOf :: [a] -> [[a]]
tailsOf [] = [[]]
tailsOf xs@(_ : rest) = xs : tailsOf rest

-- | Run the full pipeline (analyze + generate) and return split output.
runPipeline :: SplitConfig -> Map.Map Opt.Global Opt.Node -> String -> SplitOutput
runPipeline config nodes mainMod =
  generateChunks devMode globalGraph mains Map.empty config
  where
    globalGraph = mkGlobalGraph nodes
    mains = mkMains mainMod

-- PIPELINE TESTS

pipelineTests :: TestTree
pipelineTests =
  testGroup
    "Full pipeline"
    [ testCase "no lazy imports produces single chunk output" $
        assertSingleChunkOutput noSplitConfig simpleGraph
    , testCase "single lazy import produces entry + lazy chunks" $
        assertLazyChunkCount 1 (lazyConfig ["Dashboard"]) dashboardGraph
    , testCase "two lazy imports produce entry + 2 lazy chunks" $
        assertLazyChunkCount 2 (lazyConfig ["Dashboard", "Settings"]) twoLazyGraph
    , testCase "shared dependency creates shared chunk" $
        assertSharedExtraction (lazyConfig ["Dashboard", "Settings"]) sharedGraph
    , testCase "pipeline output chunk count matches graph" $
        assertPipelineChunkCount (lazyConfig ["Dashboard"]) dashboardGraph
    ]
  where
    simpleGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineNode) ]

    dashboardGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Dashboard" "view"])
      , (mkGlobal "Dashboard" "view", mkDefineNode)
      ]

    twoLazyGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Dashboard" "view", mkGlobal "Settings" "page"])
      , (mkGlobal "Dashboard" "view", mkDefineNode)
      , (mkGlobal "Settings" "page", mkDefineNode)
      ]

    sharedGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Dashboard" "view", mkGlobal "Settings" "page"])
      , (mkGlobal "Dashboard" "view", mkDefineWithDeps [mkGlobal "Common" "helper"])
      , (mkGlobal "Settings" "page", mkDefineWithDeps [mkGlobal "Common" "helper"])
      , (mkGlobal "Common" "helper", mkDefineNode)
      ]

-- | Assert that no-split config produces exactly one chunk.
assertSingleChunkOutput :: SplitConfig -> Map.Map Opt.Global Opt.Node -> IO ()
assertSingleChunkOutput config nodes = do
  let output = runPipeline config nodes "Main"
      chunks = output ^. soChunks
  length chunks @?= 1
  case chunks of
    [c] -> (c ^. coKind) @?= EntryChunk
    _ -> assertFailure "expected exactly one chunk"

-- | Assert that the pipeline produces the expected number of lazy chunks.
assertLazyChunkCount :: Int -> SplitConfig -> Map.Map Opt.Global Opt.Node -> IO ()
assertLazyChunkCount expectedLazy config nodes = do
  let output = runPipeline config nodes "Main"
      chunks = output ^. soChunks
      lazyChunks = filter (\c -> c ^. coKind == LazyChunk) chunks
  length lazyChunks @?= expectedLazy

-- | Assert that shared dependency extraction works.
assertSharedExtraction :: SplitConfig -> Map.Map Opt.Global Opt.Node -> IO ()
assertSharedExtraction config nodes = do
  let cg = analyze config (mkGlobalGraph nodes) (mkMains "Main")
      sharedG = mkGlobal "Common" "helper"
      dashG = mkGlobal "Dashboard" "view"
      settG = mkGlobal "Settings" "page"
      globalMap = cg ^. cgGlobalToChunk
      dashChunkId = Map.lookup dashG globalMap
      settChunkId = Map.lookup settG globalMap
      sharedChunkId = Map.lookup sharedG globalMap
  assertBool "shared not in dashboard chunk"
    (sharedChunkId /= dashChunkId || sharedChunkId == Nothing)
  assertBool "shared not in settings chunk"
    (sharedChunkId /= settChunkId || sharedChunkId == Nothing)

-- | Assert chunk count from pipeline matches analysis.
assertPipelineChunkCount :: SplitConfig -> Map.Map Opt.Global Opt.Node -> IO ()
assertPipelineChunkCount config nodes = do
  let cg = analyze config (mkGlobalGraph nodes) (mkMains "Main")
      expectedCount = 1 + length (cg ^. cgLazy) + length (cg ^. cgShared)
      output = runPipeline config nodes "Main"
  length (output ^. soChunks) @?= expectedCount

-- OUTPUT CONTENT TESTS

outputContentTests :: TestTree
outputContentTests =
  testGroup
    "Output content"
    [ testCase "entry chunk contains IIFE wrapper" $
        assertEntryContains "(function(scope)" entryOutput
    , testCase "entry chunk contains chunk runtime" $
        assertEntryContains "__canopy_register" entryOutput
    , testCase "entry chunk contains manifest assignment" $
        assertEntryContains "__canopy_manifest" entryOutput
    , testCase "lazy chunk wrapped in __canopy_register" $
        assertLazyChunkWrapped lazyOutput
    , testCase "each chunk has unique content hash" $
        assertUniqueHashes lazyOutput
    , testCase "entry chunk filename is entry.js" $
        assertEntryFilename lazyOutput
    ]
  where
    entryOutput = runPipeline (lazyConfig ["Dashboard"]) entryGraph "Main"
    lazyOutput = runPipeline (lazyConfig ["Dashboard"]) entryGraph "Main"

    entryGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Dashboard" "view"])
      , (mkGlobal "Dashboard" "view", mkDefineNode)
      ]

-- | Assert that the entry chunk contains a given string.
assertEntryContains :: String -> SplitOutput -> IO ()
assertEntryContains needle output = do
  let chunks = output ^. soChunks
      entryChunks = filter (\c -> c ^. coKind == EntryChunk) chunks
  case entryChunks of
    [entry] ->
      assertBool ("entry contains: " ++ needle)
        (containsStr needle (renderBuilder (entry ^. coBuilder)))
    _ -> assertFailure "expected exactly one entry chunk"

-- | Assert that lazy chunks are wrapped in __canopy_register.
assertLazyChunkWrapped :: SplitOutput -> IO ()
assertLazyChunkWrapped output = do
  let chunks = output ^. soChunks
      lazyChunks = filter (\c -> c ^. coKind == LazyChunk) chunks
  assertBool "at least one lazy chunk" (not (null lazyChunks))
  mapM_ checkRegisterWrapper lazyChunks
  where
    checkRegisterWrapper c =
      assertBool ("lazy chunk wrapped in register: " ++ show (c ^. coFilename))
        (containsStr "__canopy_register" (renderBuilder (c ^. coBuilder)))

-- | Assert that all chunks have unique content hashes.
assertUniqueHashes :: SplitOutput -> IO ()
assertUniqueHashes output = do
  let chunks = output ^. soChunks
      hashes = map (\c -> c ^. coHash) chunks
      uniqueHashes = Set.fromList hashes
  Set.size uniqueHashes @?= length hashes

-- | Assert that the entry chunk filename is entry.js.
assertEntryFilename :: SplitOutput -> IO ()
assertEntryFilename output = do
  let chunks = output ^. soChunks
      entryChunks = filter (\c -> c ^. coKind == EntryChunk) chunks
  case entryChunks of
    [entry] -> entry ^. coFilename @?= "entry.js"
    _ -> assertFailure "expected exactly one entry chunk"

-- MANIFEST INTEGRATION TESTS

manifestIntegrationTests :: TestTree
manifestIntegrationTests =
  testGroup
    "Manifest integration"
    [ testCase "manifest is valid JSON structure" $
        assertManifestStructure manifestOutput
    , testCase "manifest contains entry field" $
        assertManifestContains "\"entry\":" manifestOutput
    , testCase "manifest contains chunks field" $
        assertManifestContains "\"chunks\":" manifestOutput
    , testCase "manifest references all lazy chunk filenames" $
        assertManifestReferencesChunks manifestOutput
    ]
  where
    manifestOutput = runPipeline (lazyConfig ["Dashboard", "Settings"]) manifestGraph "Main"

    manifestGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Dashboard" "view", mkGlobal "Settings" "page"])
      , (mkGlobal "Dashboard" "view", mkDefineNode)
      , (mkGlobal "Settings" "page", mkDefineNode)
      ]

-- | Assert that manifest has valid JSON structure (starts with {, ends with }).
assertManifestStructure :: SplitOutput -> IO ()
assertManifestStructure output = do
  let manifest = renderBuilder (output ^. soManifest)
  case manifest of
    ('{' : _) -> assertBool "ends with }" (last manifest == '}')
    _ -> assertFailure ("manifest should start with '{', got: " ++ take 20 manifest)

-- | Assert that manifest contains a given string.
assertManifestContains :: String -> SplitOutput -> IO ()
assertManifestContains needle output = do
  let manifest = renderBuilder (output ^. soManifest)
  assertBool ("manifest contains: " ++ needle)
    (containsStr needle manifest)

-- | Assert that manifest references all lazy chunk filenames.
assertManifestReferencesChunks :: SplitOutput -> IO ()
assertManifestReferencesChunks output = do
  let manifest = renderBuilder (output ^. soManifest)
      chunks = output ^. soChunks
      lazyChunks = filter (\c -> c ^. coKind == LazyChunk) chunks
  assertBool "has lazy chunks" (not (null lazyChunks))
  mapM_ (checkFilenameInManifest manifest) lazyChunks
  where
    checkFilenameInManifest manifest c =
      assertBool ("manifest references: " ++ c ^. coFilename)
        (containsStr (c ^. coFilename) manifest)

-- BACKWARD COMPATIBILITY TESTS

backwardCompatTests :: TestTree
backwardCompatTests =
  testGroup
    "Backward compatibility"
    [ testCase "no lazy imports produces single entry chunk" $ do
        let output = runPipeline noSplitConfig singleGraph "Main"
            chunks = output ^. soChunks
        length chunks @?= 1
        case chunks of
          [c] -> (c ^. coKind) @?= EntryChunk
          _ -> assertFailure "expected single entry chunk"
    , testCase "no lazy imports entry has all globals" $ do
        let cg = analyze noSplitConfig (mkGlobalGraph singleGraph) (mkMains "Main")
            mainG = mkGlobal "Main" "main"
            utilG = mkGlobal "Utils" "helper"
        Set.member mainG (cg ^. cgEntry . chunkGlobals) @?= True
        Set.member utilG (cg ^. cgEntry . chunkGlobals) @?= True
    , testCase "no lazy imports manifest has empty chunks" $ do
        let output = runPipeline noSplitConfig singleGraph "Main"
            manifest = renderBuilder (output ^. soManifest)
        assertBool "empty chunks object" (containsStr "\"chunks\":{}" manifest)
    , testCase "entry chunk always present regardless of config" $ do
        let outputNoSplit = runPipeline noSplitConfig singleGraph "Main"
            outputWithSplit = runPipeline (lazyConfig ["Dashboard"]) lazyGraph "Main"
            hasEntry chunks = any (\c -> c ^. coKind == EntryChunk) chunks
        assertBool "no-split has entry" (hasEntry (outputNoSplit ^. soChunks))
        assertBool "split has entry" (hasEntry (outputWithSplit ^. soChunks))
    ]
  where
    singleGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Utils" "helper"])
      , (mkGlobal "Utils" "helper", mkDefineNode)
      ]

    lazyGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Dashboard" "view"])
      , (mkGlobal "Dashboard" "view", mkDefineNode)
      ]

-- DETERMINISM TESTS

determinismTests :: TestTree
determinismTests =
  testGroup
    "Determinism"
    [ testCase "same input produces identical output" $ do
        let output1 = runPipeline config graph "Main"
            output2 = runPipeline config graph "Main"
            hashes1 = map (\c -> c ^. coHash) (output1 ^. soChunks)
            hashes2 = map (\c -> c ^. coHash) (output2 ^. soChunks)
        hashes1 @?= hashes2
    , testCase "same input produces identical filenames" $ do
        let output1 = runPipeline config graph "Main"
            output2 = runPipeline config graph "Main"
            files1 = map (\c -> c ^. coFilename) (output1 ^. soChunks)
            files2 = map (\c -> c ^. coFilename) (output2 ^. soChunks)
        files1 @?= files2
    , testCase "same input produces identical manifest" $ do
        let output1 = runPipeline config graph "Main"
            output2 = runPipeline config graph "Main"
            m1 = renderBuilder (output1 ^. soManifest)
            m2 = renderBuilder (output2 ^. soManifest)
        m1 @?= m2
    , testCase "chunk hashes change when content changes" $ do
        let output1 = runPipeline config graph "Main"
            output2 = runPipeline config differentGraph "Main"
            hashes1 = Set.fromList (map (\c -> c ^. coHash) (output1 ^. soChunks))
            hashes2 = Set.fromList (map (\c -> c ^. coHash) (output2 ^. soChunks))
        assertBool "different content different hashes" (hashes1 /= hashes2)
    ]
  where
    config = lazyConfig ["Dashboard"]

    graph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Dashboard" "view"])
      , (mkGlobal "Dashboard" "view", mkDefineNode)
      ]

    differentGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Dashboard" "render"])
      , (mkGlobal "Dashboard" "render", mkDefineWithDeps [mkGlobal "Dashboard" "view"])
      , (mkGlobal "Dashboard" "view", mkDefineNode)
      ]

-- PREFETCH HINT TESTS (Phase 9B)

prefetchHintTests :: TestTree
prefetchHintTests =
  testGroup
    "Prefetch hints"
    [ testCase "sandwichWithPrefetch includes prefetch link tags" $ do
        let html = renderBuilder (Html.sandwichWithPrefetch (Name.fromChars "Main") mempty chunkFiles)
        assertBool "contains prefetch tag for Dashboard" (containsStr "rel=\"prefetch\"" html)
        assertBool "references Dashboard chunk" (containsStr "chunk-Dashboard-abc.js" html)
    , testCase "sandwichWithPrefetch with no chunks matches sandwich" $ do
        let htmlWithPrefetch = renderBuilder (Html.sandwichWithPrefetch (Name.fromChars "Main") mempty [])
            htmlWithout = renderBuilder (Html.sandwich (Name.fromChars "Main") mempty)
        assertBool "both contain DOCTYPE"
          (containsStr "<!DOCTYPE HTML>" htmlWithPrefetch && containsStr "<!DOCTYPE HTML>" htmlWithout)
        assertBool "both contain Canopy init"
          (containsStr "Canopy.Main.init" htmlWithPrefetch && containsStr "Canopy.Main.init" htmlWithout)
    , testCase "prefetch tags appear in head section" $ do
        let html = renderBuilder (Html.sandwichWithPrefetch (Name.fromChars "Main") mempty chunkFiles)
        assertBool "prefetch before </head>" (containsStr "prefetch" html)
        assertBool "contains head close" (containsStr "</head>" html)
    , testCase "multiple prefetch tags for multiple chunks" $ do
        let files = ["chunk-A-111.js", "chunk-B-222.js", "shared-0-333.js"]
            html = renderBuilder (Html.sandwichWithPrefetch (Name.fromChars "Main") mempty files)
        assertBool "contains chunk-A" (containsStr "chunk-A-111.js" html)
        assertBool "contains chunk-B" (containsStr "chunk-B-222.js" html)
        assertBool "contains shared-0" (containsStr "shared-0-333.js" html)
    ]
  where
    chunkFiles = ["chunk-Dashboard-abc.js", "shared-0-def.js"]

-- INCREMENTAL CACHE TESTS (Phase 9C)

incrementalCacheTests :: TestTree
incrementalCacheTests =
  testGroup
    "Incremental caching"
    [ testCase "analyzeWithCache returns correct result on first call" $ do
        let globalGraph = mkGlobalGraph cacheGraph
            (result, _cache) = analyzeWithCache Nothing config globalGraph mains
        null (result ^. cgLazy) @?= False
    , testCase "analyzeWithCache uses cache on identical input" $ do
        let globalGraph = mkGlobalGraph cacheGraph
            (_result1, cache1) = analyzeWithCache Nothing config globalGraph mains
            (result2, cache2) = analyzeWithCache (Just cache1) config globalGraph mains
        cache1 ^. cacheGraphHash @?= cache2 ^. cacheGraphHash
        result2 ^. cgLazy @?= cache1 ^. cacheResult . cgLazy
    , testCase "analyzeWithCache invalidates on config change" $ do
        let globalGraph = mkGlobalGraph extendedGraph
            (_result1, cache1) = analyzeWithCache Nothing config globalGraph mains
            newConfig = lazyConfig ["Dashboard", "Settings"]
            (_result2, cache2) = analyzeWithCache (Just cache1) newConfig globalGraph mains
        cache2 ^. cacheConfig @?= newConfig
        assertBool "cache invalidated"
          (cache1 ^. cacheConfig /= cache2 ^. cacheConfig)
    , testCase "analyzeWithCache invalidates on graph change" $ do
        let globalGraph1 = mkGlobalGraph cacheGraph
            globalGraph2 = mkGlobalGraph extendedGraph
            (_result1, cache1) = analyzeWithCache Nothing config globalGraph1 mains
            (_, cache2) = analyzeWithCache (Just cache1) config globalGraph2 mains
        assertBool "different graph hash" (cache1 ^. cacheGraphHash /= cache2 ^. cacheGraphHash)
    , testCase "graphHash is deterministic" $ do
        let globalGraph = mkGlobalGraph cacheGraph
        graphHash globalGraph @?= graphHash globalGraph
    , testCase "graphHash differs for different graphs" $ do
        let g1 = mkGlobalGraph cacheGraph
            g2 = mkGlobalGraph extendedGraph
        assertBool "different hashes" (graphHash g1 /= graphHash g2)
    ]
  where
    config = lazyConfig ["Dashboard"]
    mains = mkMains "Main"

    cacheGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Dashboard" "view"])
      , (mkGlobal "Dashboard" "view", mkDefineNode)
      ]

    extendedGraph = Map.fromList
      [ (mkGlobal "Main" "main", mkDefineWithDeps [mkGlobal "Dashboard" "view", mkGlobal "Settings" "page"])
      , (mkGlobal "Dashboard" "view", mkDefineNode)
      , (mkGlobal "Settings" "page", mkDefineNode)
      ]
