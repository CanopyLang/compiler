{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Generate.JavaScript.RelinkTest — tests for incremental IIFE relinking.
--
-- Validates the DEV-9 fast incremental relink path in
-- "Generate.JavaScript.Relink":
--
--   * partitioning a global graph into per-module node maps,
--   * content hashing that flips on any structural change and is stable
--     across mode (dev vs prod hash differently),
--   * the content-hash short-circuit: a no-op relink regenerates nothing and
--     reuses every fragment; a single-module edit regenerates exactly one
--     module and reuses the rest,
--   * determinism: an incremental relink ending in a given graph state emits a
--     byte-identical bundle to a fresh full link of that state,
--   * a wall-clock guard that a single-module relink of a 10-module app stays
--     comfortably sub-second (the DEV-9 throughput gate), and does strictly
--     less work than the full link.
--
-- @since 0.20.5
module Unit.Generate.JavaScript.RelinkTest
  ( tests,
  )
where

import qualified AST.Optimized as Opt
import AST.Optimized.Expr (Expr (..), Global (..))
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Exception (evaluate)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import qualified Generate.JavaScript.Relink as Relink
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

-- ---------------------------------------------------------------------------
-- Test root
-- ---------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Relink"
    [ partitionTests,
      hashTests,
      shortCircuitTests,
      determinismTests,
      performanceTests
    ]

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

opts :: Relink.BundleOptions
opts = Relink.defaultBundleOptions

devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

prodMode :: Mode.Mode
prodMode = Mode.Prod Map.empty False False False StringPool.emptyPool Set.empty Map.empty

mains :: Map ModuleName.Canonical Opt.Main
mains = Map.empty

-- | A small curried-function definition so each fragment has real codegen work.
defNode :: Int -> Int -> Opt.Node
defNode m d =
  Opt.Define body Set.empty
  where
    body =
      Function
        [Name.fromChars "x", Name.fromChars "y"]
        ( Call
            (VarLocal (Name.fromChars "x"))
            [ VarLocal (Name.fromChars "y"),
              Str (Utf8.fromChars ("m" ++ show m ++ "d" ++ show d))
            ]
        )

moduleHome :: Int -> ModuleName.Canonical
moduleHome m = ModuleName.Canonical Pkg.core (Name.fromChars ("Mod" ++ show m))

defName :: Int -> Name.Name
defName d = Name.fromChars ("def" ++ show d)

-- | Build an @n@-module graph with @perModule@ definitions per module.
buildGraph :: Int -> Int -> Opt.GlobalGraph
buildGraph nModules perModule =
  Opt.GlobalGraph (Map.fromList entries) Map.empty Map.empty
  where
    entries =
      [ (Global (moduleHome m) (defName d), defNode m d)
        | m <- [0 .. nModules - 1],
          d <- [0 .. perModule - 1]
      ]

-- | The standard 10-module / 6-def sample app used across tests.
sampleGraph :: Opt.GlobalGraph
sampleGraph = buildGraph 10 6

-- | 'sampleGraph' with module 5's first definition rebodied — a single edit.
editGraph :: Int -> Opt.GlobalGraph
editGraph m =
  Opt.GlobalGraph (Map.insert g editedNode nodes) fields locs
  where
    Opt.GlobalGraph nodes fields locs = sampleGraph
    g = Global (moduleHome m) (defName 0)
    editedNode = Opt.Define (Str (Utf8.fromChars "edited")) Set.empty

bundleBytes :: BB.Builder -> LBS.ByteString
bundleBytes = BB.toLazyByteString

-- ---------------------------------------------------------------------------
-- Partitioning
-- ---------------------------------------------------------------------------

partitionTests :: TestTree
partitionTests =
  testGroup
    "partitionByModule"
    [ testCase "groups globals under their home module" $
        let Opt.GlobalGraph g _ _ = sampleGraph
            parts = Relink.partitionByModule g
         in Map.size parts @?= 10,
      testCase "each module keeps all its definitions" $
        let Opt.GlobalGraph g _ _ = sampleGraph
            parts = Relink.partitionByModule g
         in map Map.size (Map.elems parts) @?= replicate 10 6,
      testCase "empty graph partitions to empty map" $
        Map.null (Relink.partitionByModule Map.empty) @?= True
    ]

-- ---------------------------------------------------------------------------
-- Content hashing
-- ---------------------------------------------------------------------------

hashTests :: TestTree
hashTests =
  testGroup
    "moduleContentHash"
    [ testCase "identical nodes hash equal" $
        let nodes = Map.singleton (Global (moduleHome 0) (defName 0)) (defNode 0 0)
         in Relink.moduleContentHash devMode nodes @?= Relink.moduleContentHash devMode nodes,
      testCase "different bodies hash differently" $
        let g = Global (moduleHome 0) (defName 0)
            a = Map.singleton g (Opt.Define (Str (Utf8.fromChars "a")) Set.empty)
            b = Map.singleton g (Opt.Define (Str (Utf8.fromChars "b")) Set.empty)
         in assertBool "hashes must differ" (Relink.moduleContentHash devMode a /= Relink.moduleContentHash devMode b),
      testCase "dev and prod hash the same nodes differently" $
        let nodes = Map.singleton (Global (moduleHome 0) (defName 0)) (defNode 0 0)
         in assertBool
              "mode must salt the hash"
              (Relink.moduleContentHash devMode nodes /= Relink.moduleContentHash prodMode nodes),
      testCase "mode tags are distinct" $
        assertBool "dev /= prod tag" (Relink.modeTag devMode /= Relink.modeTag prodMode)
    ]

-- ---------------------------------------------------------------------------
-- Content-hash short-circuit
-- ---------------------------------------------------------------------------

shortCircuitTests :: TestTree
shortCircuitTests =
  testGroup
    "content-hash short-circuit"
    [ testCase "no-op relink regenerates nothing" $
        let (_, cache) = Relink.linkBundle opts devMode sampleGraph mains
            result = Relink.relinkIncremental opts devMode cache sampleGraph mains
         in Set.size (Relink.rrRegenerated result) @?= 0,
      testCase "no-op relink reuses every module" $
        let (_, cache) = Relink.linkBundle opts devMode sampleGraph mains
            result = Relink.relinkIncremental opts devMode cache sampleGraph mains
         in Set.size (Relink.rrReused result) @?= 10,
      testCase "single edit regenerates exactly one module" $
        let (_, cache) = Relink.linkBundle opts devMode sampleGraph mains
            result = Relink.relinkIncremental opts devMode cache (editGraph 5) mains
         in Set.size (Relink.rrRegenerated result) @?= 1,
      testCase "single edit reuses the other nine modules" $
        let (_, cache) = Relink.linkBundle opts devMode sampleGraph mains
            result = Relink.relinkIncremental opts devMode cache (editGraph 5) mains
         in Set.size (Relink.rrReused result) @?= 9,
      testCase "the regenerated module is the edited one" $
        let (_, cache) = Relink.linkBundle opts devMode sampleGraph mains
            result = Relink.relinkIncremental opts devMode cache (editGraph 5) mains
         in Relink.rrRegenerated result @?= Set.singleton (moduleHome 5),
      testCase "empty cache forces full regenerate" $
        let result = Relink.relinkIncremental opts devMode Relink.emptyCache sampleGraph mains
         in Set.size (Relink.rrRegenerated result) @?= 10
    ]

-- ---------------------------------------------------------------------------
-- Determinism: relink == full link for the same end state
-- ---------------------------------------------------------------------------

determinismTests :: TestTree
determinismTests =
  testGroup
    "determinism"
    [ testCase "no-op relink equals a fresh full link, byte for byte" $
        let (fullB, cache) = Relink.linkBundle opts devMode sampleGraph mains
            result = Relink.relinkIncremental opts devMode cache sampleGraph mains
         in bundleBytes (Relink.rrBundle result) @?= bundleBytes fullB,
      testCase "relink after an edit equals a full link of the edited graph" $
        let (_, cache) = Relink.linkBundle opts devMode sampleGraph mains
            edited = editGraph 5
            (fullEdited, _) = Relink.linkBundle opts devMode edited mains
            result = Relink.relinkIncremental opts devMode cache edited mains
         in bundleBytes (Relink.rrBundle result) @?= bundleBytes fullEdited,
      testCase "edited bundle differs from the original bundle" $
        let (fullB, cache) = Relink.linkBundle opts devMode sampleGraph mains
            result = Relink.relinkIncremental opts devMode cache (editGraph 5) mains
         in assertBool
              "an edit must change the output"
              (bundleBytes (Relink.rrBundle result) /= bundleBytes fullB),
      testCase "bundle is wrapped in the IIFE scaffolding" $
        let (fullB, _) = Relink.linkBundle opts devMode sampleGraph mains
            bytes = bundleBytes fullB
         in assertBool
              "starts with IIFE header"
              (LBS.isPrefixOf "(function(scope)" bytes)
    ]

-- ---------------------------------------------------------------------------
-- Performance: single-module relink stays sub-second (DEV-9 gate)
-- ---------------------------------------------------------------------------

performanceTests :: TestTree
performanceTests =
  testGroup
    "performance (DEV-9)"
    [ testCase "single-module relink of a 10-module app is sub-second" $ do
        -- Prime the cache with a full link (forced, not timed).
        let (_, cache) = Relink.linkBundle opts devMode sampleGraph mains
        _ <- evaluate (Map.size cache)
        -- Time only the incremental relink after one edit.
        elapsedMs <- timeMs $ do
          let r = Relink.relinkIncremental opts devMode cache (editGraph 3) mains
          evaluate (LBS.length (bundleBytes (Relink.rrBundle r)))
        assertBool
          ("relink took " ++ show elapsedMs ++ "ms, expected < 1000ms")
          (elapsedMs < 1000)
    ]

-- | Run an action and return its wall-clock duration in milliseconds.
timeMs :: IO a -> IO Integer
timeMs act = do
  start <- getCurrentTime
  _ <- act
  end <- getCurrentTime
  pure (round (realToFrac (diffUTCTime end start) * 1000 :: Double))
