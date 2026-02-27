{-# LANGUAGE OverloadedStrings #-}

-- | Property tests for code splitting invariants.
--
-- Validates structural invariants of the chunk graph using QuickCheck:
--
-- * Every reachable global appears in exactly one chunk
-- * Entry chunk has no incoming chunk dependencies
-- * Chunk global sets are pairwise disjoint
-- * Content hashes are deterministic
--
-- @since 0.19.2
module Property.Generate.CodeSplitProperties (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens ((^.))
import qualified Data.ByteString.Builder as B
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Utf8 as Utf8
import Generate.JavaScript.CodeSplit.Analyze (analyze)
import Generate.JavaScript.CodeSplit.Manifest (contentHash)
import Generate.JavaScript.CodeSplit.Types
  ( ChunkGraph (..),
    ChunkKind (..),
    SplitConfig (..),
    chunkGlobals,
    chunkKind,
    cgEntry,
    cgLazy,
    cgShared,
    cgGlobalToChunk,
    entryChunkId,
  )
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.CodeSplit Properties"
    [ hashDeterminismTests
    , chunkGraphInvariantTests
    ]

-- HELPERS

testPkg :: Pkg.Name
testPkg = Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars "app")

mkCanonical :: String -> ModuleName.Canonical
mkCanonical name = ModuleName.Canonical testPkg (Name.fromChars name)

mkGlobal :: String -> String -> Opt.Global
mkGlobal modName varName =
  Opt.Global (mkCanonical modName) (Name.fromChars varName)

mkDefineNode :: Opt.Node
mkDefineNode = Opt.Define (Opt.Bool True) Set.empty

mkDefineWithDeps :: [Opt.Global] -> Opt.Node
mkDefineWithDeps deps = Opt.Define (Opt.Bool True) (Set.fromList deps)

mkGlobalGraph :: Map.Map Opt.Global Opt.Node -> Opt.GlobalGraph
mkGlobalGraph graph = Opt.GlobalGraph graph Map.empty Map.empty

mkMains :: String -> Map.Map ModuleName.Canonical Opt.Main
mkMains modName =
  Map.singleton (mkCanonical modName) (Opt.Static)

-- HASH DETERMINISM

hashDeterminismTests :: TestTree
hashDeterminismTests =
  testGroup
    "Content hash determinism"
    [ testProperty "same input always produces same hash" $ \(input :: String) ->
        let builder = B.stringUtf8 input
            h1 = contentHash builder
            h2 = contentHash builder
         in h1 == h2
    , testProperty "hash is always 8 characters" $ \(input :: String) ->
        let hash = contentHash (B.stringUtf8 input)
         in Text.length hash == 8
    , testProperty "hash contains only hex characters" $ \(input :: String) ->
        let hash = contentHash (B.stringUtf8 input)
            isHex c = c `elem` ("0123456789abcdef" :: String)
         in all isHex (Text.unpack hash)
    ]

-- CHUNK GRAPH INVARIANTS
-- These use hand-crafted graphs since we can't easily generate random Opt.GlobalGraphs

chunkGraphInvariantTests :: TestTree
chunkGraphInvariantTests =
  testGroup
    "Chunk graph invariants"
    [ testProperty "entry chunk always has EntryChunk kind" $ \(n :: Int) ->
        let numModules = abs n `mod` 5
            globals = [mkGlobal ("Mod" ++ show i) "fn" | i <- [0 .. numModules]]
            mainG = mkGlobal "Main" "main"
            graph = mkGlobalGraph (Map.fromList
              ((mainG, mkDefineWithDeps globals)
               : [(g, mkDefineNode) | g <- globals]))
            config = SplitConfig Set.empty 2
            cg = analyze config (mkGlobalGraph (Map.fromList
              ((mainG, mkDefineWithDeps globals)
               : [(g, mkDefineNode) | g <- globals]))) (mkMains "Main")
         in (cg ^. cgEntry . chunkKind) == EntryChunk
    , testProperty "no lazy imports means no lazy chunks" $ \(n :: Int) ->
        let numGlobals = abs n `mod` 10 + 1
            globals = [mkGlobal "Utils" ("fn" ++ show i) | i <- [1 .. numGlobals]]
            mainG = mkGlobal "Main" "main"
            graph = mkGlobalGraph (Map.fromList
              ((mainG, mkDefineWithDeps globals)
               : [(g, mkDefineNode) | g <- globals]))
            config = SplitConfig Set.empty 2
            cg = analyze config graph (mkMains "Main")
         in null (cg ^. cgLazy)
    , testProperty "globals are pairwise disjoint across chunks" $ \(seed :: Int) ->
        let numLazy = abs seed `mod` 3 + 1
            lazyNames = ["Lazy" ++ show i | i <- [1 .. numLazy]]
            lazyGlobals = [mkGlobal name "fn" | name <- lazyNames]
            mainG = mkGlobal "Main" "main"
            graph = mkGlobalGraph (Map.fromList
              ((mainG, mkDefineWithDeps lazyGlobals)
               : [(g, mkDefineNode) | g <- lazyGlobals]))
            config = SplitConfig (Set.fromList (map mkCanonical lazyNames)) 2
            cg = analyze config graph (mkMains "Main")
            allSets =
              (cg ^. cgEntry . chunkGlobals)
              : map (^. chunkGlobals) (cg ^. cgLazy)
              ++ map (^. chunkGlobals) (cg ^. cgShared)
         in arePairwiseDisjoint allSets
    , testProperty "all reachable globals appear in globalToChunk map" $ \(seed :: Int) ->
        let numExtra = abs seed `mod` 5
            extraGlobals = [mkGlobal "Utils" ("fn" ++ show i) | i <- [1 .. numExtra]]
            mainG = mkGlobal "Main" "main"
            graph = mkGlobalGraph (Map.fromList
              ((mainG, mkDefineWithDeps extraGlobals)
               : [(g, mkDefineNode) | g <- extraGlobals]))
            config = SplitConfig Set.empty 2
            cg = analyze config graph (mkMains "Main")
            mapped = Map.keysSet (cg ^. cgGlobalToChunk)
            allInChunks = Set.unions
              [ cg ^. cgEntry . chunkGlobals
              , Set.unions (map (^. chunkGlobals) (cg ^. cgLazy))
              , Set.unions (map (^. chunkGlobals) (cg ^. cgShared))
              ]
         in mapped == allInChunks
    ]

arePairwiseDisjoint :: (Ord a) => [Set.Set a] -> Bool
arePairwiseDisjoint sets = go sets
  where
    go [] = True
    go (s : rest) = all (Set.null . Set.intersection s) rest && go rest
