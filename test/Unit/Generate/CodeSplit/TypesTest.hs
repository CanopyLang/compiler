{-# LANGUAGE OverloadedStrings #-}

-- | Tests for code splitting types.
--
-- Validates the core data types, lenses, and helper functions used
-- throughout the code splitting pipeline.
--
-- @since 0.19.2
module Unit.Generate.CodeSplit.TypesTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens ((&), (.~), (^.))
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.Set as Set
import qualified Data.Utf8 as Utf8
import Generate.JavaScript.CodeSplit.Types
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.CodeSplit.Types"
    [ chunkIdTests
    , chunkKindTests
    , lensTests
    , helperTests
    , splitConfigTests
    ]

-- HELPERS

testPkg :: Pkg.Name
testPkg = Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars "app")

mkCanonical :: String -> ModuleName.Canonical
mkCanonical name = ModuleName.Canonical testPkg (Name.fromChars name)

mkGlobal :: String -> String -> Opt.Global
mkGlobal modName varName =
  Opt.Global (mkCanonical modName) (Name.fromChars varName)

-- CHUNK ID TESTS

chunkIdTests :: TestTree
chunkIdTests =
  testGroup
    "ChunkId"
    [ testCase "entry chunk ID is entry" $
        entryChunkId @?= ChunkId "entry"
    , testCase "ChunkId equality" $
        ChunkId "foo" @?= ChunkId "foo"
    , testCase "ChunkId inequality" $
        assertBool "different IDs" (ChunkId "foo" /= ChunkId "bar")
    , testCase "ChunkId ordering" $
        assertBool "alphabetical" (ChunkId "aaa" < ChunkId "bbb")
    ]

-- CHUNK KIND TESTS

chunkKindTests :: TestTree
chunkKindTests =
  testGroup
    "ChunkKind"
    [ testCase "EntryChunk equality" $
        EntryChunk @?= EntryChunk
    , testCase "LazyChunk equality" $
        LazyChunk @?= LazyChunk
    , testCase "SharedChunk equality" $
        SharedChunk @?= SharedChunk
    , testCase "different kinds are not equal" $ do
        assertBool "entry /= lazy" (EntryChunk /= LazyChunk)
        assertBool "lazy /= shared" (LazyChunk /= SharedChunk)
        assertBool "entry /= shared" (EntryChunk /= SharedChunk)
    , testCase "ChunkKind ordering" $
        assertBool "entry < lazy" (EntryChunk < LazyChunk)
    ]

-- LENS TESTS

lensTests :: TestTree
lensTests =
  testGroup
    "Lenses"
    [ testCase "chunkId lens reads correctly" $ do
        let chunk = Chunk entryChunkId EntryChunk Set.empty Set.empty Nothing
        (chunk ^. chunkId) @?= entryChunkId
    , testCase "chunkKind lens reads correctly" $ do
        let chunk = Chunk entryChunkId EntryChunk Set.empty Set.empty Nothing
        (chunk ^. chunkKind) @?= EntryChunk
    , testCase "chunkGlobals lens reads correctly" $ do
        let g = mkGlobal "Main" "main"
            chunk = Chunk entryChunkId EntryChunk (Set.singleton g) Set.empty Nothing
        Set.member g (chunk ^. chunkGlobals) @?= True
    , testCase "chunkDeps lens reads correctly" $ do
        let dep = ChunkId "lazy-foo"
            chunk = Chunk entryChunkId EntryChunk Set.empty (Set.singleton dep) Nothing
        Set.member dep (chunk ^. chunkDeps) @?= True
    , testCase "chunkModule lens reads correctly" $ do
        let modName = mkCanonical "Dashboard"
            chunk = Chunk (ChunkId "lazy-Dashboard") LazyChunk Set.empty Set.empty (Just modName)
        (chunk ^. chunkModule) @?= Just modName
    , testCase "SplitConfig scLazyModules lens" $ do
        let config = SplitConfig (Set.singleton (mkCanonical "Foo")) 2
        Set.size (config ^. scLazyModules) @?= 1
    , testCase "SplitConfig scMinSharedRefs lens" $ do
        let config = SplitConfig Set.empty 3
        (config ^. scMinSharedRefs) @?= 3
    , testCase "chunkKind lens sets correctly" $ do
        let chunk = Chunk entryChunkId EntryChunk Set.empty Set.empty Nothing
            updated = chunk & chunkKind .~ LazyChunk
        (updated ^. chunkKind) @?= LazyChunk
    , testCase "cgEntry lens reads entry chunk" $ do
        let entry = Chunk entryChunkId EntryChunk Set.empty Set.empty Nothing
            cg = ChunkGraph entry [] [] Map.empty
        (cg ^. cgEntry . chunkId) @?= entryChunkId
    , testCase "cgLazy lens reads lazy chunks" $ do
        let entry = Chunk entryChunkId EntryChunk Set.empty Set.empty Nothing
            lazy1 = Chunk (ChunkId "lazy-A") LazyChunk Set.empty Set.empty Nothing
            cg = ChunkGraph entry [lazy1] [] Map.empty
        length (cg ^. cgLazy) @?= 1
    , testCase "cgShared lens reads shared chunks" $ do
        let entry = Chunk entryChunkId EntryChunk Set.empty Set.empty Nothing
            shared1 = Chunk (ChunkId "shared-0") SharedChunk Set.empty Set.empty Nothing
            cg = ChunkGraph entry [] [shared1] Map.empty
        length (cg ^. cgShared) @?= 1
    , testCase "cgGlobalToChunk lens reads mapping" $ do
        let g = mkGlobal "Main" "main"
            entry = Chunk entryChunkId EntryChunk (Set.singleton g) Set.empty Nothing
            mapping = Map.singleton g entryChunkId
            cg = ChunkGraph entry [] [] mapping
        Map.lookup g (cg ^. cgGlobalToChunk) @?= Just entryChunkId
    ]

-- HELPER FUNCTION TESTS

helperTests :: TestTree
helperTests =
  testGroup
    "Helper functions"
    [ testCase "isEntryChunk True for entry ID" $
        isEntryChunk entryChunkId @?= True
    , testCase "isEntryChunk False for lazy ID" $
        isEntryChunk (ChunkId "lazy-foo") @?= False
    , testCase "isEntryChunk False for shared ID" $
        isEntryChunk (ChunkId "shared-0") @?= False
    , testCase "entryChunkId value" $
        entryChunkId @?= ChunkId "entry"
    ]

-- SPLIT CONFIG TESTS

splitConfigTests :: TestTree
splitConfigTests =
  testGroup
    "SplitConfig"
    [ testCase "empty config has no lazy modules" $ do
        let config = SplitConfig Set.empty 2
        Set.null (config ^. scLazyModules) @?= True
    , testCase "config with lazy modules" $ do
        let mods = Set.fromList [mkCanonical "A", mkCanonical "B"]
            config = SplitConfig mods 2
        Set.size (config ^. scLazyModules) @?= 2
    , testCase "minSharedRefs stored correctly" $ do
        let config = SplitConfig Set.empty 5
        (config ^. scMinSharedRefs) @?= 5
    ]
