{-# LANGUAGE OverloadedStrings #-}

-- | Tests for tree-shaking metrics computation.
--
-- Validates that the 'TreeShakeReport' correctly counts total, reachable,
-- and eliminated definitions by constructing synthetic dependency graphs
-- with known reachability properties.
--
-- @since 0.19.2
module Unit.Generate.TreeShakeTest (tests) where

import AST.Optimized.Expr (Expr (..), Global (..))
import qualified AST.Optimized.Graph as Opt
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
      reachabilityTests
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

-- HELPERS: Test data construction

testPackage :: Pkg.Name
testPackage = Pkg.core

testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical testPackage (Name.fromChars "Main")

otherHome :: ModuleName.Canonical
otherHome = ModuleName.Canonical testPackage (Name.fromChars "Helper")

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
