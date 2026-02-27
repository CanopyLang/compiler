{-# LANGUAGE OverloadedStrings #-}

-- | Hashing benchmarks for the Canopy compiler.
--
-- Measures SHA-256 hashing throughput for content of varying sizes,
-- which is used for incremental compilation cache invalidation
-- and lock file integrity verification.
--
-- @since 0.19.1
module Bench.Hash (benchmarks) where

import Criterion.Main (Benchmark)
import qualified Criterion.Main as Criterion
import qualified Builder.Hash as Hash
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC

-- | All hash benchmarks.
benchmarks :: Benchmark
benchmarks =
  Criterion.bgroup
    "Hash"
    [ Criterion.bench "hash 100 bytes" (Criterion.whnf Hash.hashBytes smallContent),
      Criterion.bench "hash 1 KB" (Criterion.whnf Hash.hashBytes mediumContent),
      Criterion.bench "hash 10 KB" (Criterion.whnf Hash.hashBytes largeContent),
      Criterion.bench "hash 100 KB" (Criterion.whnf Hash.hashBytes veryLargeContent),
      Criterion.bench "hash string (100 chars)" (Criterion.whnf Hash.hashString smallString),
      Criterion.bench "hash string (10K chars)" (Criterion.whnf Hash.hashString largeString),
      Criterion.bench "hash comparison (equal)" (Criterion.whnf (Hash.hashesEqual h1) h1),
      Criterion.bench "hash comparison (different)" (Criterion.whnf (Hash.hashesEqual h1) h2),
      Criterion.bench "hex roundtrip" (Criterion.whnf hexRoundtrip h1)
    ]

-- Test data

smallContent :: BS.ByteString
smallContent = BSC.pack (replicate 100 'a')

mediumContent :: BS.ByteString
mediumContent = BSC.pack (replicate 1024 'b')

largeContent :: BS.ByteString
largeContent = BSC.pack (replicate 10240 'c')

veryLargeContent :: BS.ByteString
veryLargeContent = BSC.pack (replicate 102400 'd')

smallString :: String
smallString = replicate 100 'e'

largeString :: String
largeString = replicate 10000 'f'

h1 :: Hash.ContentHash
h1 = Hash.hashBytes (BSC.pack "test content 1")

h2 :: Hash.ContentHash
h2 = Hash.hashBytes (BSC.pack "test content 2")

-- | Roundtrip through hex string representation.
hexRoundtrip :: Hash.ContentHash -> Maybe Hash.HashValue
hexRoundtrip ch = Hash.fromHexString (Hash.toHexString (Hash.hashValue ch))
