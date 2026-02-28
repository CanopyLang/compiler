{-# LANGUAGE OverloadedStrings #-}

-- | Tree-shaking analysis benchmarks for the Canopy compiler.
--
-- Measures the throughput of reachability analysis on dependency graphs
-- of varying sizes.  Tree-shaking determines which definitions are
-- reachable from the entry points so the code generator can omit dead
-- code.  This benchmark exercises the graph traversal at scale.
--
-- @since 0.19.2
module Bench.TreeShake (benchmarks) where

import AST.Optimized.Expr (Expr (..), Global (..))
import qualified AST.Optimized.Graph as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Criterion.Main (Benchmark)
import qualified Criterion.Main as Criterion
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Generate.TreeShake (TreeShakeReport, computeReport, reachableGlobals)

-- | All tree-shaking benchmarks.
benchmarks :: Benchmark
benchmarks =
  Criterion.bgroup
    "TreeShake"
    [ Criterion.bench "reachability 100 nodes (linear chain)" (Criterion.whnf benchReachableLinear 100),
      Criterion.bench "reachability 1000 nodes (linear chain)" (Criterion.whnf benchReachableLinear 1000),
      Criterion.bench "reachability 100 nodes (50% dead)" (Criterion.whnf benchReachableHalfDead 100),
      Criterion.bench "reachability 1000 nodes (50% dead)" (Criterion.whnf benchReachableHalfDead 1000),
      Criterion.bench "report 100 nodes (linear)" (Criterion.whnf benchReportLinear 100),
      Criterion.bench "report 1000 nodes (linear)" (Criterion.whnf benchReportLinear 1000),
      Criterion.bench "report 100 nodes (50% dead)" (Criterion.whnf benchReportHalfDead 100),
      Criterion.bench "report 1000 nodes (50% dead)" (Criterion.whnf benchReportHalfDead 1000),
      Criterion.bench "report 5000 nodes (binary tree)" (Criterion.whnf benchReportBinaryTree 12),
      Criterion.bench "report 100 nodes (fully connected)" (Criterion.whnf benchReportFullyConnected 100)
    ]

-- BENCHMARK DRIVERS

-- | Benchmark reachability on a linear chain of N nodes.
benchReachableLinear :: Int -> Int
benchReachableLinear n =
  Set.size (reachableGlobals (linearChainGraph n) singleMain)

-- | Benchmark reachability on a graph where half the nodes are dead.
benchReachableHalfDead :: Int -> Int
benchReachableHalfDead n =
  Set.size (reachableGlobals (halfDeadGraph n) singleMain)

-- | Benchmark report computation on a linear chain.
benchReportLinear :: Int -> TreeShakeReport
benchReportLinear n =
  computeReport (linearChainGraph n) singleMain

-- | Benchmark report computation on a half-dead graph.
benchReportHalfDead :: Int -> TreeShakeReport
benchReportHalfDead n =
  computeReport (halfDeadGraph n) singleMain

-- | Benchmark report on a binary tree graph (2^n - 1 nodes).
benchReportBinaryTree :: Int -> TreeShakeReport
benchReportBinaryTree depth =
  computeReport (binaryTreeGraph depth) singleMain

-- | Benchmark report on a fully connected graph.
benchReportFullyConnected :: Int -> TreeShakeReport
benchReportFullyConnected n =
  computeReport (fullyConnectedGraph n) singleMain

-- GRAPH CONSTRUCTORS

-- | Package for test globals.
testPkg :: Pkg.Name
testPkg = Pkg.core

-- | Home module for test globals.
testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical testPkg (Name.fromChars "Main")

-- | Entry point for all benchmarks.
singleMain :: Map.Map ModuleName.Canonical Opt.Main
singleMain = Map.singleton testHome Opt.Static

-- | Create a global with a numbered name.
mkGlobal :: Int -> Global
mkGlobal i = Global testHome (Name.fromChars ("g" ++ show i))

-- | The main global (g0).
mainGlobal :: Global
mainGlobal = Global testHome (Name.fromChars "main")

-- | Build a GlobalGraph from node entries.
mkGraph :: [(Global, Opt.Node)] -> Opt.GlobalGraph
mkGraph entries =
  Opt.GlobalGraph (Map.fromList entries) Map.empty Map.empty

-- | Simple expression for nodes.
simpleExpr :: Expr
simpleExpr = Bool True

-- | Linear chain: main -> g1 -> g2 -> ... -> gN.
--
-- All nodes are reachable through a single chain.
linearChainGraph :: Int -> Opt.GlobalGraph
linearChainGraph n =
  mkGraph (mainNode : innerNodes ++ [lastNode])
  where
    mainNode = (mainGlobal, Opt.Define simpleExpr (Set.singleton (mkGlobal 1)))
    innerNodes = [(mkGlobal i, Opt.Define simpleExpr (Set.singleton (mkGlobal (i + 1)))) | i <- [1 .. n - 1]]
    lastNode = (mkGlobal n, Opt.Define simpleExpr Set.empty)

-- | Half-dead graph: main -> g1 -> ... -> g(n/2), plus dead_1 ... dead_(n/2).
--
-- The first half forms a reachable chain; the second half is unreachable.
halfDeadGraph :: Int -> Opt.GlobalGraph
halfDeadGraph n =
  mkGraph (mainNode : reachableNodes ++ deadNodes)
  where
    half = n `div` 2
    mainNode = (mainGlobal, Opt.Define simpleExpr (Set.singleton (mkGlobal 1)))
    reachableNodes = [(mkGlobal i, Opt.Define simpleExpr deps) | i <- [1 .. half], let deps = if i < half then Set.singleton (mkGlobal (i + 1)) else Set.empty]
    deadNodes = [(mkDead i, Opt.Define simpleExpr Set.empty) | i <- [1 .. half]]
    mkDead i = Global testHome (Name.fromChars ("dead" ++ show i))

-- | Binary tree graph with the given depth.
--
-- Each node has two children. Total nodes = 2^depth - 1.
-- All nodes are reachable from the root (main).
binaryTreeGraph :: Int -> Opt.GlobalGraph
binaryTreeGraph depth =
  mkGraph (mainNode : treeNodes)
  where
    mainNode = (mainGlobal, Opt.Define simpleExpr (Set.singleton (mkGlobal 1)))
    treeNodes = concatMap makeLevel [0 .. depth - 1]
    makeLevel level =
      [ (mkGlobal idx, Opt.Define simpleExpr (childDeps idx level))
        | offset <- [0 .. 2 ^ level - 1],
          let idx = 2 ^ level + offset
      ]
    childDeps idx level
      | level >= depth - 1 = Set.empty
      | otherwise = Set.fromList [mkGlobal (idx * 2), mkGlobal (idx * 2 + 1)]

-- | Fully connected graph: every node depends on every other node.
--
-- This is the worst case for reachability since the traversal must
-- visit every edge.  All nodes are reachable from main.
fullyConnectedGraph :: Int -> Opt.GlobalGraph
fullyConnectedGraph n =
  mkGraph (mainNode : allNodes)
  where
    allGlobals = Set.fromList (map mkGlobal [1 .. n])
    mainNode = (mainGlobal, Opt.Define simpleExpr allGlobals)
    allNodes = [(mkGlobal i, Opt.Define simpleExpr (Set.delete (mkGlobal i) allGlobals)) | i <- [1 .. n]]
