{-# LANGUAGE OverloadedStrings #-}

-- | Canopy compiler benchmark suite.
--
-- Provides criterion-based benchmarks for the core compilation pipeline:
-- parsing, JSON codec, hashing, code generation, optimization, and
-- tree-shaking analysis.
--
-- Run with: @stack bench canopy:canopy-bench@
--
-- @since 0.19.1
module Main (main) where

import Criterion.Main (defaultMain)
import qualified Bench.Cache as Cache
import qualified Bench.Generate as Generate
import qualified Bench.Hash as Hash
import qualified Bench.Json as Json
import qualified Bench.Optimize as Optimize
import qualified Bench.Parse as Parse
import qualified Bench.TreeShake as TreeShake

main :: IO ()
main =
  defaultMain
    [ Parse.benchmarks,
      Json.benchmarks,
      Hash.benchmarks,
      Generate.benchmarks,
      Optimize.benchmarks,
      TreeShake.benchmarks,
      Cache.benchmarks
    ]
