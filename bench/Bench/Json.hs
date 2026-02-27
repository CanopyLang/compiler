{-# LANGUAGE OverloadedStrings #-}

-- | JSON codec benchmarks for the Canopy compiler.
--
-- Measures encoding and decoding throughput for Canopy's custom
-- JSON codec used in build artifacts, package manifests, and
-- diagnostic output.
--
-- @since 0.19.1
module Bench.Json (benchmarks) where

import Criterion.Main (Benchmark)
import qualified Criterion.Main as Criterion
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import qualified Json.Encode as Encode
import qualified Json.String as Json

-- | All JSON benchmarks.
benchmarks :: Benchmark
benchmarks =
  Criterion.bgroup
    "Json"
    [ encodeBenchmarks,
      stringBenchmarks
    ]

-- | Encoding benchmarks.
encodeBenchmarks :: Benchmark
encodeBenchmarks =
  Criterion.bgroup
    "Encode"
    [ Criterion.bench "small object (5 fields)" (Criterion.nf encodeToLBS smallObject),
      Criterion.bench "medium object (20 fields)" (Criterion.nf encodeToLBS mediumObject),
      Criterion.bench "nested object (3 levels)" (Criterion.nf encodeToLBS nestedObject),
      Criterion.bench "array of 100 ints" (Criterion.nf encodeToLBS intArray),
      Criterion.bench "array of 50 strings" (Criterion.nf encodeToLBS stringArray),
      Criterion.bench "ugly encode small" (Criterion.nf encodeUglyToLBS smallObject),
      Criterion.bench "ugly encode medium" (Criterion.nf encodeUglyToLBS mediumObject)
    ]

-- | String encoding benchmarks.
stringBenchmarks :: Benchmark
stringBenchmarks =
  Criterion.bgroup
    "String"
    [ Criterion.bench "short string (10 chars)" (Criterion.whnf Json.fromChars "helloworld"),
      Criterion.bench "medium string (100 chars)" (Criterion.whnf Json.fromChars mediumString),
      Criterion.bench "string with escapes" (Criterion.whnf Json.fromChars escapedString)
    ]

-- | Encode to lazy ByteString (forces evaluation).
encodeToLBS :: Encode.Value -> LBS.ByteString
encodeToLBS = Builder.toLazyByteString . Encode.encode

-- | Encode ugly (no whitespace) to lazy ByteString.
encodeUglyToLBS :: Encode.Value -> LBS.ByteString
encodeUglyToLBS = Builder.toLazyByteString . Encode.encodeUgly

-- Test data

smallObject :: Encode.Value
smallObject =
  Encode.object
    [ (Json.fromChars "name", Encode.chars "MyModule"),
      (Json.fromChars "version", Encode.chars "1.0.0"),
      (Json.fromChars "type", Encode.chars "application"),
      (Json.fromChars "source-directories", Encode.list Encode.chars ["src"]),
      (Json.fromChars "dependencies", Encode.object [])
    ]

mediumObject :: Encode.Value
mediumObject =
  Encode.object
    (map makeField [1 .. 20 :: Int])
  where
    makeField i =
      (Json.fromChars ("field" ++ show i), Encode.int i)

nestedObject :: Encode.Value
nestedObject =
  Encode.object
    [ (Json.fromChars "level1", level1)
    ]
  where
    level1 =
      Encode.object
        [ (Json.fromChars "a", Encode.int 1),
          (Json.fromChars "b", level2)
        ]
    level2 =
      Encode.object
        [ (Json.fromChars "c", Encode.int 2),
          (Json.fromChars "d", level3)
        ]
    level3 =
      Encode.object
        [ (Json.fromChars "e", Encode.int 3),
          (Json.fromChars "f", Encode.list Encode.int [1 .. 10])
        ]

intArray :: Encode.Value
intArray = Encode.list Encode.int [1 .. 100]

stringArray :: Encode.Value
stringArray =
  Encode.list Encode.chars
    (map (\i -> "item_" ++ show (i :: Int)) [1 .. 50])

mediumString :: String
mediumString = replicate 100 'x'

escapedString :: String
escapedString =
  "Hello \"world\" with \\backslashes\\ and\nnewlines\tand\ttabs"
