{-# LANGUAGE OverloadedStrings #-}

-- | Code generation benchmarks for the Canopy compiler.
--
-- Measures source map encoding throughput and VLQ encoding
-- performance, which are critical for development build speed.
--
-- @since 0.19.1
module Bench.Generate (benchmarks) where

import Criterion.Main (Benchmark)
import qualified Criterion.Main as Criterion
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import qualified Generate.JavaScript.SourceMap as SourceMap

-- | All code generation benchmarks.
benchmarks :: Benchmark
benchmarks =
  Criterion.bgroup
    "Generate"
    [ sourceMapBenchmarks
    ]

-- | Source map encoding benchmarks.
sourceMapBenchmarks :: Benchmark
sourceMapBenchmarks =
  Criterion.bgroup
    "SourceMap"
    [ Criterion.bench "encode 100 mappings" (Criterion.nf serializeMap smallMap),
      Criterion.bench "encode 1000 mappings" (Criterion.nf serializeMap mediumMap),
      Criterion.bench "encode 5000 mappings" (Criterion.nf serializeMap largeMap),
      Criterion.bench "add 100 mappings" (Criterion.whnf (addMappings 100) emptyMap),
      Criterion.bench "add 1000 mappings" (Criterion.whnf (addMappings 1000) emptyMap)
    ]

-- | Serialize a source map to bytes (forces full evaluation).
serializeMap :: SourceMap.SourceMap -> LBS.ByteString
serializeMap = Builder.toLazyByteString . SourceMap.toBuilder

-- | Add N mappings to a source map.
addMappings :: Int -> SourceMap.SourceMap -> SourceMap.SourceMap
addMappings n sm = foldl (flip SourceMap.addMapping) sm (makeMappings n)

emptyMap :: SourceMap.SourceMap
emptyMap =
  snd (SourceMap.addSource "src/Main.can" Nothing (SourceMap.empty "output.js"))

-- | Create a source map with N mappings across multiple lines.
buildMap :: Int -> SourceMap.SourceMap
buildMap n =
  foldl (flip SourceMap.addMapping) withSource (makeMappings n)
  where
    withSource = snd (SourceMap.addSource "src/Main.can" Nothing (SourceMap.empty "output.js"))

smallMap :: SourceMap.SourceMap
smallMap = buildMap 100

mediumMap :: SourceMap.SourceMap
mediumMap = buildMap 1000

largeMap :: SourceMap.SourceMap
largeMap = buildMap 5000

-- | Generate N realistic mapping entries.
makeMappings :: Int -> [SourceMap.Mapping]
makeMappings n =
  [ SourceMap.Mapping
      { SourceMap._mGenLine = i `div` 10,
        SourceMap._mGenCol = (i `mod` 10) * 8,
        SourceMap._mSrcIndex = 0,
        SourceMap._mSrcLine = i `div` 5,
        SourceMap._mSrcCol = (i `mod` 5) * 4,
        SourceMap._mNameIndex = Nothing
      }
    | i <- [0 .. n - 1]
  ]
