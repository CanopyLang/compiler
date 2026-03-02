{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Binary serialization benchmarks for the Canopy compiler.
--
-- Measures the round-trip performance of the 'Binary' codec used
-- for @.elco@ cache files.  This is important because every
-- incremental build reads and writes cached module artifacts.
--
-- @since 0.19.2
module Bench.Cache (benchmarks) where

import qualified AST.Optimized as Opt
import qualified Canopy.Interface as Interface
import qualified Canopy.Package as Pkg
import Criterion.Main (Benchmark)
import qualified Criterion.Main as Criterion
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map

-- | All cache benchmarks.
benchmarks :: Benchmark
benchmarks =
  Criterion.bgroup
    "Cache"
    [ Criterion.bench "encode empty interface" (Criterion.nf Binary.encode emptyInterface),
      Criterion.bench "decode empty interface" (Criterion.whnf decodeInterface encodedEmptyInterface),
      Criterion.bench "encode empty graph" (Criterion.nf Binary.encode emptyGraph),
      Criterion.bench "decode empty graph" (Criterion.whnf decodeGraph encodedEmptyGraph),
      Criterion.bench "round-trip interface" (Criterion.nf roundTripInterface encodedEmptyInterface),
      Criterion.bench "round-trip graph" (Criterion.nf roundTripGraph encodedEmptyGraph)
    ]

-- | Decode an Interface from bytes.
decodeInterface :: LBS.ByteString -> Interface.Interface
decodeInterface = Binary.decode

-- | Decode a LocalGraph from bytes.
decodeGraph :: LBS.ByteString -> Opt.LocalGraph
decodeGraph = Binary.decode

-- | Decode then re-encode an Interface (full round-trip).
--
-- Forces the result via 'Binary.encode' which produces 'LBS.ByteString'
-- (has 'NFData'), avoiding the need for an 'NFData Interface' instance.
roundTripInterface :: LBS.ByteString -> LBS.ByteString
roundTripInterface bytes =
  Binary.encode (Binary.decode bytes :: Interface.Interface)

-- | Decode then re-encode a LocalGraph (full round-trip).
roundTripGraph :: LBS.ByteString -> LBS.ByteString
roundTripGraph bytes =
  Binary.encode (Binary.decode bytes :: Opt.LocalGraph)

-- | A minimal Interface for benchmarking.
emptyInterface :: Interface.Interface
emptyInterface =
  Interface.Interface Pkg.core Map.empty Map.empty Map.empty Map.empty Map.empty

-- | Pre-encoded bytes for the empty interface.
encodedEmptyInterface :: LBS.ByteString
encodedEmptyInterface = Binary.encode emptyInterface

-- | A minimal LocalGraph for benchmarking.
emptyGraph :: Opt.LocalGraph
emptyGraph =
  Opt.LocalGraph Nothing Map.empty Map.empty Map.empty

-- | Pre-encoded bytes for the empty graph.
encodedEmptyGraph :: LBS.ByteString
encodedEmptyGraph = Binary.encode emptyGraph
