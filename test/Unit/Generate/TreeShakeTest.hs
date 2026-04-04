{-# LANGUAGE OverloadedStrings #-}

-- | Tests for tree-shaking metrics computation.
--
-- Validates that the 'TreeShakeReport' correctly counts total, reachable,
-- and eliminated definitions by constructing synthetic dependency graphs
-- with known reachability properties.
--
-- == Test Coverage
--
-- * Report computation for empty, single, and mixed graphs
-- * Reachability traversal for transitive and dead definitions
-- * Node type handling: Define, DefineTailFunc, Ctor, Enum, Box, Link, PortIncoming, PortOutgoing
-- * Large graph stress test (100+ nodes) for chain reachability
-- * Multiple entry points with overlapping and disjoint reachable sets
--
-- @since 0.19.2
module Unit.Generate.TreeShakeTest (tests) where

import AST.Optimized.Expr (Expr (..), Global (..))
import qualified AST.Optimized.Graph as Opt
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Generate.TreeShake (TreeShakeReport (..), computeReport, reachableGlobals)
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

tests :: TestTree
tests =
  Test.testGroup
    "Generate.TreeShake"
    [ reportTests,
      reachabilityTests,
      nodeTypeTests,
      largeGraphTests,
      multipleEntryPointTests
    ]

-- | Tests for TreeShakeReport computation.
reportTests :: TestTree
reportTests =
  Test.testGroup
    "Report"
    [ Test.testCase "empty graph has zero totals" $
        computeReport emptyGraph emptyMains @?= TreeShakeReport 0 0 0,
      Test.testCase "single reachable def yields zero eliminated" $
        computeReport singleNodeGraph singleMain @?= TreeShakeReport 1 1 0,
      Test.testCase "unreachable def is eliminated" $
        computeReport twoNodeOneReachableGraph singleMain @?= TreeShakeReport 2 1 1,
      Test.testCase "all defs reachable through chain" $
        computeReport chainGraph singleMain @?= TreeShakeReport 3 3 0,
      Test.testCase "mixed reachable and unreachable" $
        computeReport mixedGraph singleMain @?= TreeShakeReport 4 2 2
    ]

-- | Tests for reachability computation.
reachabilityTests :: TestTree
reachabilityTests =
  Test.testGroup
    "Reachability"
    [ Test.testCase "empty graph yields empty reachable set" $
        Set.size (reachableGlobals emptyGraph emptyMains) @?= 0,
      Test.testCase "main is always reachable" $
        Set.member mainGlobal (reachableGlobals singleNodeGraph singleMain) @?= True,
      Test.testCase "transitive dependency is reachable" $
        Set.member helperGlobal (reachableGlobals chainGraph singleMain) @?= True,
      Test.testCase "unreachable def is not in set" $
        Set.member deadGlobal (reachableGlobals twoNodeOneReachableGraph singleMain) @?= False,
      Test.testCase "reachable count matches graph traversal" $
        Set.size (reachableGlobals mixedGraph singleMain) @?= 2
    ]

-- | Tests for various Node constructor types in the dependency graph.
--
-- Verifies that 'reachableGlobals' traverses Node variants correctly:
-- 'DefineTailFunc' follows its dep set, 'Box'/'Ctor'/'Enum' have no deps,
-- 'Link' forwards to its target global, and 'PortIncoming'/'PortOutgoing'
-- follow their dep sets.
nodeTypeTests :: TestTree
nodeTypeTests =
  Test.testGroup
    "Node type handling"
    [ Test.testCase "DefineTailFunc dep is reachable" $
        let tailNode = Opt.DefineTailFunc [Name.fromChars "n"] simpleExpr (Set.singleton helperGlobal)
            helperNode = Opt.Define simpleExpr Set.empty
            graph = mkGraph [(mainGlobal, tailNode), (helperGlobal, helperNode)]
         in Set.member helperGlobal (reachableGlobals graph singleMain) @?= True,
      Test.testCase "Box node has no transitive deps" $
        let boxNode = Opt.Box
            graph = mkGraph [(mainGlobal, Opt.Define simpleExpr (Set.singleton helperGlobal)), (helperGlobal, boxNode)]
         in Set.size (reachableGlobals graph singleMain) @?= 2,
      Test.testCase "Ctor node contributes no further deps" $
        let ctorNode = Opt.Ctor Index.first 1
            graph = mkGraph [(mainGlobal, Opt.Define simpleExpr (Set.singleton helperGlobal)), (helperGlobal, ctorNode)]
         in Set.size (reachableGlobals graph singleMain) @?= 2,
      Test.testCase "Enum node contributes no further deps" $
        let enumNode = Opt.Enum Index.first
            graph = mkGraph [(mainGlobal, Opt.Define simpleExpr (Set.singleton helperGlobal)), (helperGlobal, enumNode)]
         in Set.size (reachableGlobals graph singleMain) @?= 2,
      Test.testCase "Link node forwards reachability to its target" $
        let linkNode = Opt.Link utilGlobal
            utilNode = Opt.Define simpleExpr Set.empty
            graph = mkGraph
              [ (mainGlobal, Opt.Define simpleExpr (Set.singleton helperGlobal)),
                (helperGlobal, linkNode),
                (utilGlobal, utilNode)
              ]
         in Set.member utilGlobal (reachableGlobals graph singleMain) @?= True,
      Test.testCase "PortIncoming dep is reachable" $
        let portNode = Opt.PortIncoming simpleExpr (Set.singleton utilGlobal)
            utilNode = Opt.Define simpleExpr Set.empty
            graph = mkGraph
              [ (mainGlobal, Opt.Define simpleExpr (Set.singleton helperGlobal)),
                (helperGlobal, portNode),
                (utilGlobal, utilNode)
              ]
         in Set.member utilGlobal (reachableGlobals graph singleMain) @?= True,
      Test.testCase "PortOutgoing dep is reachable" $
        let portNode = Opt.PortOutgoing simpleExpr (Set.singleton utilGlobal)
            utilNode = Opt.Define simpleExpr Set.empty
            graph = mkGraph
              [ (mainGlobal, Opt.Define simpleExpr (Set.singleton helperGlobal)),
                (helperGlobal, portNode),
                (utilGlobal, utilNode)
              ]
         in Set.member utilGlobal (reachableGlobals graph singleMain) @?= True
    ]

-- | Stress tests for large graphs.
--
-- Verifies that a 100-node linear chain is fully traversed and that the
-- report counts all nodes as reachable with zero eliminated.
largeGraphTests :: TestTree
largeGraphTests =
  Test.testGroup
    "large graph stress tests"
    [ Test.testCase "100-node chain: all nodes reachable" $
        let n = 100
            graph = buildChainGraph n
            total = n + 1
         in Set.size (reachableGlobals graph singleMain) @?= total,
      Test.testCase "100-node chain: report shows zero eliminated" $
        let n = 100
            graph = buildChainGraph n
            total = n + 1
         in computeReport graph singleMain @?= TreeShakeReport total total 0,
      Test.testCase "50-node chain with 50 dead nodes: 50 eliminated" $
        let chainN = 50
            deadN = 50
            chainG = buildChainGraph chainN
            chainTotal = chainN + 1
            deadNodes = [(makeIndexedGlobal (chainN + i), Opt.Define simpleExpr Set.empty) | i <- [0 .. deadN - 1]]
            graph = addNodesToGraph deadNodes chainG
         in computeReport graph singleMain @?= TreeShakeReport (chainTotal + deadN) chainTotal deadN
    ]

-- | Tests for multiple entry points in the dependency graph.
--
-- Verifies that when multiple module mains are provided the reachable
-- set is the union of all reachable nodes from each entry point.
multipleEntryPointTests :: TestTree
multipleEntryPointTests =
  Test.testGroup
    "multiple entry points"
    [ Test.testCase "two disjoint entry points each reach their own def" $
        let graph = mkGraph
              [ (mainGlobal, Opt.Define simpleExpr Set.empty),
                (secondMain, Opt.Define simpleExpr Set.empty)
              ]
         in Set.size (reachableGlobals graph twoMains) @?= 2,
      Test.testCase "two entry points with shared dep: dep counted once" $
        let graph = mkGraph
              [ (mainGlobal, Opt.Define simpleExpr (Set.singleton utilGlobal)),
                (secondMain, Opt.Define simpleExpr (Set.singleton utilGlobal)),
                (utilGlobal, Opt.Define simpleExpr Set.empty)
              ]
         in Set.size (reachableGlobals graph twoMains) @?= 3,
      Test.testCase "two entry points: dead node not reachable from either" $
        let graph = mkGraph
              [ (mainGlobal, Opt.Define simpleExpr Set.empty),
                (secondMain, Opt.Define simpleExpr Set.empty),
                (deadGlobal, Opt.Define simpleExpr Set.empty)
              ]
         in computeReport graph twoMains @?= TreeShakeReport 3 2 1
    ]

-- HELPERS: Test data construction

testPackage :: Pkg.Name
testPackage = Pkg.core

testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical testPackage (Name.fromChars "Main")

otherHome :: ModuleName.Canonical
otherHome = ModuleName.Canonical testPackage (Name.fromChars "Helper")

secondHome :: ModuleName.Canonical
secondHome = ModuleName.Canonical testPackage (Name.fromChars "Second")

mainGlobal :: Global
mainGlobal = Global testHome (Name.fromChars "main")

helperGlobal :: Global
helperGlobal = Global testHome (Name.fromChars "helper")

utilGlobal :: Global
utilGlobal = Global otherHome (Name.fromChars "util")

deadGlobal :: Global
deadGlobal = Global testHome (Name.fromChars "dead")

dead2Global :: Global
dead2Global = Global testHome (Name.fromChars "dead2")

secondMain :: Global
secondMain = Global secondHome (Name.fromChars "main")

-- | A simple expression for building test nodes.
simpleExpr :: Expr
simpleExpr = Bool True

mkGraph :: [(Global, Opt.Node)] -> Opt.GlobalGraph
mkGraph entries =
  Opt.GlobalGraph (Map.fromList entries) Map.empty Map.empty

emptyGraph :: Opt.GlobalGraph
emptyGraph = mkGraph []

emptyMains :: Map.Map ModuleName.Canonical Opt.Main
emptyMains = Map.empty

singleMain :: Map.Map ModuleName.Canonical Opt.Main
singleMain = Map.singleton testHome Opt.Static

twoMains :: Map.Map ModuleName.Canonical Opt.Main
twoMains = Map.fromList [(testHome, Opt.Static), (secondHome, Opt.Static)]

-- | Graph with a single node (main) that has no dependencies.
singleNodeGraph :: Opt.GlobalGraph
singleNodeGraph =
  mkGraph [(mainGlobal, Opt.Define simpleExpr Set.empty)]

-- | Graph with two nodes: main (reachable) and dead (unreachable).
twoNodeOneReachableGraph :: Opt.GlobalGraph
twoNodeOneReachableGraph =
  mkGraph
    [ (mainGlobal, Opt.Define simpleExpr Set.empty),
      (deadGlobal, Opt.Define simpleExpr Set.empty)
    ]

-- | Graph with a chain: main -> helper -> util (all reachable).
chainGraph :: Opt.GlobalGraph
chainGraph =
  mkGraph
    [ (mainGlobal, Opt.Define simpleExpr (Set.singleton helperGlobal)),
      (helperGlobal, Opt.Define simpleExpr (Set.singleton utilGlobal)),
      (utilGlobal, Opt.Define simpleExpr Set.empty)
    ]

-- | Graph with 4 nodes: main -> helper (reachable), dead and dead2 (unreachable).
mixedGraph :: Opt.GlobalGraph
mixedGraph =
  mkGraph
    [ (mainGlobal, Opt.Define simpleExpr (Set.singleton helperGlobal)),
      (helperGlobal, Opt.Define simpleExpr Set.empty),
      (deadGlobal, Opt.Define simpleExpr Set.empty),
      (dead2Global, Opt.Define simpleExpr (Set.singleton deadGlobal))
    ]

-- | Build a global with an integer suffix for large graph tests.
makeIndexedGlobal :: Int -> Global
makeIndexedGlobal i = Global testHome (Name.fromChars ("node" ++ show i))

-- | Build a linear chain graph of n nodes starting from mainGlobal.
--
-- mainGlobal -> node0 -> node1 -> ... -> node(n-2) -> node(n-1)
buildChainGraph :: Int -> Opt.GlobalGraph
buildChainGraph n =
  mkGraph (rootEntry : chainEntries)
  where
    rootEntry = (mainGlobal, Opt.Define simpleExpr (Set.singleton (makeIndexedGlobal 0)))
    chainEntries = [mkChainEntry i | i <- [0 .. n - 1]]
    mkChainEntry i
      | i < n - 1 = (makeIndexedGlobal i, Opt.Define simpleExpr (Set.singleton (makeIndexedGlobal (i + 1))))
      | otherwise = (makeIndexedGlobal i, Opt.Define simpleExpr Set.empty)

-- | Add extra (global, node) pairs to an existing GlobalGraph.
addNodesToGraph :: [(Global, Opt.Node)] -> Opt.GlobalGraph -> Opt.GlobalGraph
addNodesToGraph pairs (Opt.GlobalGraph nodes effects mains) =
  Opt.GlobalGraph (Map.union (Map.fromList pairs) nodes) effects mains
