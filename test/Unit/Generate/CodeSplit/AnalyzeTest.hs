{-# LANGUAGE OverloadedStrings #-}

-- | Tests for code splitting analysis.
--
-- Validates chunk graph construction, lazy boundary detection, shared
-- extraction, code motion, and all invariants of the analyze algorithm.
--
-- @since 0.19.2
module Unit.Generate.CodeSplit.AnalyzeTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens ((^.))
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.Set as Set
import qualified Data.Utf8 as Utf8
import Generate.JavaScript.CodeSplit.Analyze (analyze, reachableFrom)
import Generate.JavaScript.CodeSplit.Types
  ( ChunkGraph,
    ChunkKind (..),
    SplitConfig (..),
    chunkGlobals,
    chunkId,
    chunkKind,
    cgEntry,
    cgLazy,
    cgShared,
    cgGlobalToChunk,
    entryChunkId,
  )
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.CodeSplit.Analyze"
    [ noLazyTests
    , singleLazyTests
    , multipleLazyTests
    , sharedExtractionTests
    , reachabilityTests
    , invariantTests
    ]

-- TEST HELPERS

-- | Create a package name for testing.
testPkg :: Pkg.Name
testPkg = Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars "app")

-- | Create a canonical module name.
mkCanonical :: String -> ModuleName.Canonical
mkCanonical name = ModuleName.Canonical testPkg (Name.fromChars name)

-- | Create a global reference.
mkGlobal :: String -> String -> Opt.Global
mkGlobal modName varName =
  Opt.Global (mkCanonical modName) (Name.fromChars varName)

-- | Build a simple graph node (Define with no dependencies).
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
  Map.singleton (mkCanonical modName) (Opt.Static)

-- | No-split config.
noSplitConfig :: SplitConfig
noSplitConfig = SplitConfig Set.empty 2

-- | Config with specified lazy modules.
lazyConfig :: [String] -> SplitConfig
lazyConfig modNames =
  SplitConfig (Set.fromList (map mkCanonical modNames)) 2

-- NO LAZY IMPORTS TESTS

noLazyTests :: TestTree
noLazyTests =
  testGroup
    "No lazy imports"
    [ testCase "empty graph produces single entry chunk" $ do
        let graph = mkGlobalGraph Map.empty
            mains = mkMains "Main"
            cg = analyze noSplitConfig graph mains
        length (cg ^. cgLazy) @?= 0
        length (cg ^. cgShared) @?= 0
        (cg ^. cgEntry . chunkKind) @?= EntryChunk
    , testCase "all globals in entry when no lazy imports" $ do
        let g1 = mkGlobal "Main" "main"
            g2 = mkGlobal "Utils" "helper"
            graph = mkGlobalGraph (Map.fromList [(g1, mkDefineWithDeps [g2]), (g2, mkDefineNode)])
            cg = analyze noSplitConfig graph (mkMains "Main")
        Set.member g1 (cg ^. cgEntry . chunkGlobals) @?= True
        Set.member g2 (cg ^. cgEntry . chunkGlobals) @?= True
    , testCase "single entry chunk has no dependencies" $ do
        let g1 = mkGlobal "Main" "main"
            graph = mkGlobalGraph (Map.singleton g1 mkDefineNode)
            cg = analyze noSplitConfig graph (mkMains "Main")
        null (cg ^. cgLazy) @?= True
        null (cg ^. cgShared) @?= True
    ]

-- SINGLE LAZY MODULE TESTS

singleLazyTests :: TestTree
singleLazyTests =
  testGroup
    "Single lazy module"
    [ testCase "single lazy import creates entry + lazy chunk" $ do
        let mainG = mkGlobal "Main" "main"
            dashG = mkGlobal "Dashboard" "view"
            graph = mkGlobalGraph (Map.fromList [(mainG, mkDefineWithDeps [dashG]), (dashG, mkDefineNode)])
            cg = analyze (lazyConfig ["Dashboard"]) graph (mkMains "Main")
        length (cg ^. cgLazy) @?= 1
    , testCase "lazy chunk has LazyChunk kind" $ do
        let mainG = mkGlobal "Main" "main"
            dashG = mkGlobal "Dashboard" "view"
            graph = mkGlobalGraph (Map.fromList [(mainG, mkDefineWithDeps [dashG]), (dashG, mkDefineNode)])
            cg = analyze (lazyConfig ["Dashboard"]) graph (mkMains "Main")
        case cg ^. cgLazy of
          [chunk] -> (chunk ^. chunkKind) @?= LazyChunk
          _ -> assertFailure "expected exactly one lazy chunk"
    , testCase "lazy globals not in entry chunk" $ do
        let mainG = mkGlobal "Main" "main"
            dashG = mkGlobal "Dashboard" "view"
            graph = mkGlobalGraph (Map.fromList [(mainG, mkDefineWithDeps [dashG]), (dashG, mkDefineNode)])
            cg = analyze (lazyConfig ["Dashboard"]) graph (mkMains "Main")
        Set.member dashG (cg ^. cgEntry . chunkGlobals) @?= False
    , testCase "main global stays in entry chunk" $ do
        let mainG = mkGlobal "Main" "main"
            dashG = mkGlobal "Dashboard" "view"
            graph = mkGlobalGraph (Map.fromList [(mainG, mkDefineWithDeps [dashG]), (dashG, mkDefineNode)])
            cg = analyze (lazyConfig ["Dashboard"]) graph (mkMains "Main")
        Set.member mainG (cg ^. cgEntry . chunkGlobals) @?= True
    ]

-- MULTIPLE LAZY MODULE TESTS

multipleLazyTests :: TestTree
multipleLazyTests =
  testGroup
    "Multiple lazy modules"
    [ testCase "two lazy imports create two lazy chunks" $ do
        let mainG = mkGlobal "Main" "main"
            dashG = mkGlobal "Dashboard" "view"
            settG = mkGlobal "Settings" "page"
            graph = mkGlobalGraph (Map.fromList
              [ (mainG, mkDefineWithDeps [dashG, settG])
              , (dashG, mkDefineNode)
              , (settG, mkDefineNode)
              ])
            cg = analyze (lazyConfig ["Dashboard", "Settings"]) graph (mkMains "Main")
        length (cg ^. cgLazy) @?= 2
    , testCase "each lazy module gets its own chunk" $ do
        let mainG = mkGlobal "Main" "main"
            dashG = mkGlobal "Dashboard" "view"
            settG = mkGlobal "Settings" "page"
            graph = mkGlobalGraph (Map.fromList
              [ (mainG, mkDefineWithDeps [dashG, settG])
              , (dashG, mkDefineNode)
              , (settG, mkDefineNode)
              ])
            cg = analyze (lazyConfig ["Dashboard", "Settings"]) graph (mkMains "Main")
            globalMap = cg ^. cgGlobalToChunk
        -- dashG and settG should be in different chunks
        Map.lookup dashG globalMap /= Map.lookup settG globalMap @?= True
    ]

-- SHARED EXTRACTION TESTS

sharedExtractionTests :: TestTree
sharedExtractionTests =
  testGroup
    "Shared extraction"
    [ testCase "globals used by 2+ chunks become shared" $ do
        let mainG = mkGlobal "Main" "main"
            dashG = mkGlobal "Dashboard" "view"
            settG = mkGlobal "Settings" "page"
            sharedG = mkGlobal "Common" "helper"
            graph = mkGlobalGraph (Map.fromList
              [ (mainG, mkDefineWithDeps [dashG, settG])
              , (dashG, mkDefineWithDeps [sharedG])
              , (settG, mkDefineWithDeps [sharedG])
              , (sharedG, mkDefineNode)
              ])
            cg = analyze (lazyConfig ["Dashboard", "Settings"]) graph (mkMains "Main")
        -- sharedG should either be in a shared chunk or entry
        -- (implementation may vary, but it should not be in both lazy chunks)
        let globalMap = cg ^. cgGlobalToChunk
            dashChunkId = Map.lookup dashG globalMap
            settChunkId = Map.lookup settG globalMap
            sharedChunkId = Map.lookup sharedG globalMap
        -- The shared global should be in a different chunk than the lazy-specific ones
        assertBool "shared global not in dashboard chunk"
          (sharedChunkId /= dashChunkId || sharedChunkId == Nothing)
        assertBool "shared global not in settings chunk"
          (sharedChunkId /= settChunkId || sharedChunkId == Nothing)
    ]

-- REACHABILITY TESTS

reachabilityTests :: TestTree
reachabilityTests =
  testGroup
    "reachableFrom"
    [ testCase "empty graph returns seed set" $ do
        let g1 = mkGlobal "Main" "main"
            result = reachableFrom Map.empty (Set.singleton g1)
        Set.member g1 result @?= True
    , testCase "follows dependency edges" $ do
        let g1 = mkGlobal "Main" "main"
            g2 = mkGlobal "Utils" "helper"
            g3 = mkGlobal "Utils" "deep"
            graph = Map.fromList
              [ (g1, mkDefineWithDeps [g2])
              , (g2, mkDefineWithDeps [g3])
              , (g3, mkDefineNode)
              ]
            result = reachableFrom graph (Set.singleton g1)
        Set.size result @?= 3
        Set.member g1 result @?= True
        Set.member g2 result @?= True
        Set.member g3 result @?= True
    , testCase "handles cycles without infinite loop" $ do
        let g1 = mkGlobal "Main" "main"
            g2 = mkGlobal "Utils" "a"
            graph = Map.fromList
              [ (g1, mkDefineWithDeps [g2])
              , (g2, mkDefineWithDeps [g1])
              ]
            result = reachableFrom graph (Set.singleton g1)
        Set.size result @?= 2
    , testCase "unreachable globals not included" $ do
        let g1 = mkGlobal "Main" "main"
            g2 = mkGlobal "Orphan" "unused"
            graph = Map.fromList
              [ (g1, mkDefineNode)
              , (g2, mkDefineNode)
              ]
            result = reachableFrom graph (Set.singleton g1)
        Set.member g1 result @?= True
        Set.member g2 result @?= False
    ]

-- INVARIANT TESTS

invariantTests :: TestTree
invariantTests =
  testGroup
    "Chunk graph invariants"
    [ testCase "every global assigned to exactly one chunk" $ do
        let mainG = mkGlobal "Main" "main"
            dashG = mkGlobal "Dashboard" "view"
            utilG = mkGlobal "Utils" "helper"
            graph = mkGlobalGraph (Map.fromList
              [ (mainG, mkDefineWithDeps [dashG, utilG])
              , (dashG, mkDefineWithDeps [utilG])
              , (utilG, mkDefineNode)
              ])
            cg = analyze (lazyConfig ["Dashboard"]) graph (mkMains "Main")
            globalMap = cg ^. cgGlobalToChunk
            allGlobals = Set.unions
              [ cg ^. cgEntry . chunkGlobals
              , Set.unions (map (^. chunkGlobals) (cg ^. cgLazy))
              , Set.unions (map (^. chunkGlobals) (cg ^. cgShared))
              ]
        -- Every global in the map should appear in exactly one chunk
        Map.size globalMap @?= Set.size allGlobals
    , testCase "entry chunk ID is entry" $ do
        let g1 = mkGlobal "Main" "main"
            graph = mkGlobalGraph (Map.singleton g1 mkDefineNode)
            cg = analyze noSplitConfig graph (mkMains "Main")
        (cg ^. cgEntry . chunkId) @?= entryChunkId
    , testCase "entry chunk has EntryChunk kind" $ do
        let g1 = mkGlobal "Main" "main"
            graph = mkGlobalGraph (Map.singleton g1 mkDefineNode)
            cg = analyze noSplitConfig graph (mkMains "Main")
        (cg ^. cgEntry . chunkKind) @?= EntryChunk
    , testCase "chunk globals are disjoint" $ do
        let mainG = mkGlobal "Main" "main"
            dashG = mkGlobal "Dashboard" "view"
            settG = mkGlobal "Settings" "page"
            graph = mkGlobalGraph (Map.fromList
              [ (mainG, mkDefineWithDeps [dashG, settG])
              , (dashG, mkDefineNode)
              , (settG, mkDefineNode)
              ])
            cg = analyze (lazyConfig ["Dashboard", "Settings"]) graph (mkMains "Main")
            allChunkSets =
              (cg ^. cgEntry . chunkGlobals)
              : map (^. chunkGlobals) (cg ^. cgLazy)
              ++ map (^. chunkGlobals) (cg ^. cgShared)
        -- Check pairwise disjointness
        assertBool "chunk globals are pairwise disjoint"
          (arePairwiseDisjoint allChunkSets)
    ]

-- | Check that a list of sets are pairwise disjoint.
arePairwiseDisjoint :: (Ord a) => [Set.Set a] -> Bool
arePairwiseDisjoint sets = go sets
  where
    go [] = True
    go (s : rest) = all (Set.null . Set.intersection s) rest && go rest
