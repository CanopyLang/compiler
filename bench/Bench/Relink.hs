{-# LANGUAGE OverloadedStrings #-}

-- | Incremental IIFE relink benchmarks for the Canopy compiler.
--
-- These benchmarks back plan DEV-9: a single-file edit on a ~10-module app
-- must relink in well under a second. They measure the three operations on
-- the dev-loop hot path:
--
--   * @full link@ — generate every module fragment from scratch (the
--     whole-program baseline that the incremental path must beat).
--   * @relink (1 module changed)@ — the realistic single-edit case: nine
--     fragments hit the content-hash cache, one is regenerated.
--   * @relink (no change)@ — the pure short-circuit: every fragment is a
--     cache hit, so no expression code generation runs at all.
--
-- The single-module relink does ~1/10th of the code-generation work of a
-- full link, which is the DEV-9 throughput win.
--
-- Run with: @stack bench canopy:canopy-bench@
--
-- @since 0.20.5
module Bench.Relink (benchmarks) where

import qualified AST.Optimized as Opt
import AST.Optimized.Expr (Expr (..), Global (..))
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Criterion.Main (Benchmark)
import qualified Criterion.Main as Criterion
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generate.JavaScript.Relink as Relink
import qualified Generate.Mode as Mode

-- | All relink benchmarks.
benchmarks :: Benchmark
benchmarks =
  Criterion.bgroup
    "Relink"
    [ Criterion.bench "full link (10 modules)" (Criterion.nf fullLink sampleGraph),
      Criterion.bench "relink 1 changed (10 modules)" (Criterion.nf relinkOneChanged ()),
      Criterion.bench "relink no change (10 modules)" (Criterion.nf relinkNoChange ())
    ]

-- BENCH DRIVERS

-- | Force the assembled bundle bytes from a full link.
fullLink :: Opt.GlobalGraph -> LBS.ByteString
fullLink graph =
  BB.toLazyByteString (fst (Relink.linkBundle opts devMode graph mains))

-- | Relink after one module changed, forcing the new bundle bytes.
--
-- Primes the cache with the original graph, then relinks against a graph
-- where exactly one module's body differs — nine fragments are reused, one
-- is regenerated.
relinkOneChanged :: () -> LBS.ByteString
relinkOneChanged () =
  BB.toLazyByteString (Relink.rrBundle result)
  where
    result = Relink.relinkIncremental opts devMode primedCache editedGraph mains

-- | Relink against the identical graph — every fragment is a cache hit.
relinkNoChange :: () -> LBS.ByteString
relinkNoChange () =
  BB.toLazyByteString (Relink.rrBundle result)
  where
    result = Relink.relinkIncremental opts devMode primedCache sampleGraph mains

-- FIXTURES

opts :: Relink.BundleOptions
opts = Relink.defaultBundleOptions

devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

-- | No main entry points: fragment generation is driven purely by the graph
-- partition, which is what the relinker measures.
mains :: Map ModuleName.Canonical Opt.Main
mains = Map.empty

-- | Cache primed from the original 10-module graph.
primedCache :: Relink.RelinkCache
primedCache = snd (Relink.linkBundle opts devMode sampleGraph mains)

-- | A 10-module sample app, each module holding several definitions.
sampleGraph :: Opt.GlobalGraph
sampleGraph = buildGraph defsPerModule

-- | A graph identical to 'sampleGraph' except module 5's first definition has
-- a different body — exactly the shape of a single-file edit.
editedGraph :: Opt.GlobalGraph
editedGraph =
  Opt.GlobalGraph (Map.insert editedGlobal editedNode nodes) fields locs
  where
    Opt.GlobalGraph nodes fields locs = sampleGraph
    editedGlobal = Global (moduleHome 5) (defName 0)
    editedNode = Opt.Define (Str (toUtf8 "edited body")) Set.empty

-- | Number of modules and definitions per module in the sample app.
moduleCount :: Int
moduleCount = 10

defsPerModule :: Int
defsPerModule = 6

-- | Build a 'GlobalGraph' with 'moduleCount' modules, each carrying
-- 'defsPerModule' definitions whose bodies are non-trivial expressions.
buildGraph :: Int -> Opt.GlobalGraph
buildGraph perModule =
  Opt.GlobalGraph (Map.fromList entries) Map.empty Map.empty
  where
    entries =
      [ (Global (moduleHome m) (defName d), defNode m d)
        | m <- [0 .. moduleCount - 1],
          d <- [0 .. perModule - 1]
      ]

-- | A definition node: a small curried function so code generation has real
-- work to do per fragment (not a trivial literal).
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
              Str (toUtf8 ("m" ++ show m ++ "d" ++ show d)),
              Int (fromIntegral (m * 100 + d))
            ]
        )

moduleHome :: Int -> ModuleName.Canonical
moduleHome m = ModuleName.Canonical Pkg.core (Name.fromChars ("Mod" ++ show m))

defName :: Int -> Name.Name
defName d = Name.fromChars ("def" ++ show d)

-- | Build a Canopy string literal payload (the 'Str' constructor's type).
toUtf8 :: String -> Utf8.Utf8 any
toUtf8 = Utf8.fromChars
