{-# LANGUAGE OverloadedStrings #-}

-- | Optimization benchmarks for the Canopy compiler.
--
-- Measures constant folding throughput for arithmetic operations
-- of varying complexity, which is part of the optimization phase
-- between type checking and code generation.
--
-- @since 0.19.2
module Bench.Optimize (benchmarks) where

import qualified AST.Canonical as Can
import qualified AST.Optimized.Expr as Opt
import Criterion.Main (Benchmark)
import qualified Criterion.Main as Criterion
import qualified Optimize.ConstantFold as ConstantFold

-- | All optimization benchmarks.
benchmarks :: Benchmark
benchmarks =
  Criterion.bgroup
    "Optimize"
    [ constantFoldBenchmarks
    ]

-- | Constant folding benchmarks.
--
-- Tests the throughput of the arithmetic constant folder on:
-- * Integer literal pairs (fully folded)
-- * Mixed literal/variable operations (identity/absorption rules)
-- * Non-foldable expressions (pass-through)
-- * Chained operations simulating deep expression trees
constantFoldBenchmarks :: Benchmark
constantFoldBenchmarks =
  Criterion.bgroup
    "ConstantFold"
    [ Criterion.bench "int add (both literal)" (Criterion.whnf foldAdd (Opt.Int 17, Opt.Int 25)),
      Criterion.bench "int mul (both literal)" (Criterion.whnf foldMul (Opt.Int 7, Opt.Int 13)),
      Criterion.bench "int sub (both literal)" (Criterion.whnf foldSub (Opt.Int 100, Opt.Int 42)),
      Criterion.bench "int div (both literal)" (Criterion.whnf foldDiv (Opt.Int 100, Opt.Int 5)),
      Criterion.bench "identity x + 0" (Criterion.whnf foldAdd (varX, Opt.Int 0)),
      Criterion.bench "identity x * 1" (Criterion.whnf foldMul (varX, Opt.Int 1)),
      Criterion.bench "absorption x * 0" (Criterion.whnf foldMul (varX, Opt.Int 0)),
      Criterion.bench "non-foldable x + y" (Criterion.whnf foldAdd (varX, varY)),
      Criterion.bench "chain of 100 additions" (Criterion.whnf foldAddChain 100),
      Criterion.bench "chain of 1000 additions" (Criterion.whnf foldAddChain 1000),
      Criterion.bench "mixed chain 100" (Criterion.whnf foldMixedChain 100),
      Criterion.bench "mixed chain 1000" (Criterion.whnf foldMixedChain 1000)
    ]

-- | Fold an addition pair.
foldAdd :: (Opt.Expr, Opt.Expr) -> Opt.Expr
foldAdd (l, r) = ConstantFold.foldArith Can.Add l r

-- | Fold a subtraction pair.
foldSub :: (Opt.Expr, Opt.Expr) -> Opt.Expr
foldSub (l, r) = ConstantFold.foldArith Can.Sub l r

-- | Fold a multiplication pair.
foldMul :: (Opt.Expr, Opt.Expr) -> Opt.Expr
foldMul (l, r) = ConstantFold.foldArith Can.Mul l r

-- | Fold a division pair.
foldDiv :: (Opt.Expr, Opt.Expr) -> Opt.Expr
foldDiv (l, r) = ConstantFold.foldArith Can.Div l r

-- | Chain of N additions: (((1 + 2) + 3) + ... + N).
--
-- Simulates how the constant folder performs when processing a deeply
-- nested arithmetic expression where each intermediate result is foldable.
foldAddChain :: Int -> Opt.Expr
foldAddChain n = foldl step (Opt.Int 0) [1 .. n]
  where
    step acc i = ConstantFold.foldArith Can.Add acc (Opt.Int i)

-- | Mixed chain: alternates between foldable and non-foldable operations.
--
-- Even iterations fold two literals, odd iterations produce an ArithBinop
-- because one operand is a variable. This exercises both code paths.
foldMixedChain :: Int -> Opt.Expr
foldMixedChain n = foldl step (Opt.Int 0) [1 .. n]
  where
    step acc i
      | even i = ConstantFold.foldArith Can.Add acc (Opt.Int i)
      | otherwise = ConstantFold.foldArith Can.Add acc varX

-- | A sample variable expression for non-foldable benchmarks.
varX :: Opt.Expr
varX = Opt.VarLocal "x"

-- | A second variable expression for non-foldable benchmarks.
varY :: Opt.Expr
varY = Opt.VarLocal "y"
