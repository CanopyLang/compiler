
-- | Unit tests for Builder.Graph module.
--
-- Tests dependency graph construction, cycle detection,
-- topological sorting, and dependency queries.
--
-- @since 0.19.1
module Unit.Builder.GraphTest (tests) where

import qualified Builder.Graph as Graph
import qualified Data.Name as Name
import qualified Data.Set as Set
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Builder.Graph Tests"
    [ testEmptyGraph,
      testAddModule,
      testAddDependency,
      testBuildGraph,
      testTopologicalSort,
      testCycleDetection,
      testDependencyQueries
    ]

-- Helper to create test module names
mkName :: String -> Name.Name
mkName = Name.fromChars

testEmptyGraph :: TestTree
testEmptyGraph =
  testGroup
    "empty graph tests"
    [ testCase "empty graph has no modules" $
        Graph.getAllModules Graph.emptyGraph @?= [],
      testCase "empty graph has no cycles" $
        Graph.hasCycle Graph.emptyGraph @?= False,
      testCase "topological sort of empty graph is empty" $
        Graph.topologicalSort Graph.emptyGraph @?= Just []
    ]

testAddModule :: TestTree
testAddModule =
  testGroup
    "add module tests"
    [ testCase "add single module" $ do
        let graph = Graph.addModule Graph.emptyGraph (mkName "Main")
        length (Graph.getAllModules graph) @?= 1,
      testCase "add same module twice" $ do
        let graph =
              Graph.addModule
                (Graph.addModule Graph.emptyGraph (mkName "Main"))
                (mkName "Main")
        length (Graph.getAllModules graph) @?= 1,
      testCase "add multiple different modules" $ do
        let graph =
              Graph.addModule
                (Graph.addModule Graph.emptyGraph (mkName "Main"))
                (mkName "Utils")
        length (Graph.getAllModules graph) @?= 2,
      testCase "added module has no dependencies" $ do
        let graph = Graph.addModule Graph.emptyGraph (mkName "Main")
        Graph.getModuleDeps graph (mkName "Main") @?= Just Set.empty
    ]

testAddDependency :: TestTree
testAddDependency =
  testGroup
    "add dependency tests"
    [ testCase "add simple dependency" $ do
        let graph = Graph.addDependency Graph.emptyGraph (mkName "Main") (mkName "Utils")
        Graph.getModuleDeps graph (mkName "Main") @?= Just (Set.singleton (mkName "Utils")),
      testCase "add dependency creates both modules" $ do
        let graph = Graph.addDependency Graph.emptyGraph (mkName "Main") (mkName "Utils")
        length (Graph.getAllModules graph) @?= 2,
      testCase "add multiple dependencies to same module" $ do
        let graph =
              Graph.addDependency
                (Graph.addDependency Graph.emptyGraph (mkName "Main") (mkName "Utils"))
                (mkName "Main")
                (mkName "Parser")
        Graph.getModuleDeps graph (mkName "Main")
          @?= Just (Set.fromList [mkName "Utils", mkName "Parser"]),
      testCase "add dependency updates reverse deps" $ do
        let graph = Graph.addDependency Graph.emptyGraph (mkName "Main") (mkName "Utils")
        Graph.reverseDeps graph (mkName "Utils") @?= Just (Set.singleton (mkName "Main"))
    ]

testBuildGraph :: TestTree
testBuildGraph =
  testGroup
    "build graph tests"
    [ testCase "build graph from empty list" $ do
        let graph = Graph.buildGraph []
        Graph.getAllModules graph @?= [],
      testCase "build graph from single module with no deps" $ do
        let graph = Graph.buildGraph [(mkName "Main", [])]
        length (Graph.getAllModules graph) @?= 1,
      testCase "build graph from module with dependencies" $ do
        let deps = [(mkName "Main", [mkName "Utils", mkName "Parser"])]
        let graph = Graph.buildGraph deps
        Graph.getModuleDeps graph (mkName "Main")
          @?= Just (Set.fromList [mkName "Utils", mkName "Parser"]),
      testCase "build graph with multiple modules" $ do
        let deps =
              [ (mkName "Main", [mkName "Utils"]),
                (mkName "Utils", [mkName "Parser"]),
                (mkName "Parser", [])
              ]
        let graph = Graph.buildGraph deps
        length (Graph.getAllModules graph) @?= 3,
      testCase "build graph creates transitive structure" $ do
        let deps =
              [ (mkName "Main", [mkName "Utils"]),
                (mkName "Utils", [mkName "Base"])
              ]
        let graph = Graph.buildGraph deps
        let trans = Graph.transitiveDeps graph (mkName "Main")
        trans @?= Set.fromList [mkName "Utils", mkName "Base"]
    ]

testTopologicalSort :: TestTree
testTopologicalSort =
  testGroup
    "topological sort tests"
    [ testCase "sort empty graph" $
        Graph.topologicalSort Graph.emptyGraph @?= Just [],
      testCase "sort single module" $ do
        let graph = Graph.buildGraph [(mkName "Main", [])]
        Graph.topologicalSort graph @?= Just [mkName "Main"],
      testCase "sort linear dependency chain" $ do
        let deps =
              [ (mkName "Main", [mkName "Utils"]),
                (mkName "Utils", [mkName "Base"])
              ]
        let graph = Graph.buildGraph deps
        case Graph.topologicalSort graph of
          Just order -> do
            let indexOf name = lookup name (zip order [0 :: Int ..])
            let baseIdx = indexOf (mkName "Base")
            let utilsIdx = indexOf (mkName "Utils")
            let mainIdx = indexOf (mkName "Main")
            (baseIdx < utilsIdx && utilsIdx < mainIdx) @? "Base before Utils before Main"
          Nothing -> assertFailure "Expected successful sort",
      testCase "sort diamond dependency" $ do
        let deps =
              [ (mkName "Main", [mkName "Left", mkName "Right"]),
                (mkName "Left", [mkName "Base"]),
                (mkName "Right", [mkName "Base"])
              ]
        let graph = Graph.buildGraph deps
        case Graph.topologicalSort graph of
          Just order -> do
            let indexOf name = lookup name (zip order [0 :: Int ..])
            let baseIdx = indexOf (mkName "Base")
            let mainIdx = indexOf (mkName "Main")
            (baseIdx < mainIdx) @? "Base should come before Main"
          Nothing -> assertFailure "Expected successful sort"
    ]

testCycleDetection :: TestTree
testCycleDetection =
  testGroup
    "cycle detection tests"
    [ testCase "no cycle in empty graph" $
        Graph.hasCycle Graph.emptyGraph @?= False,
      testCase "no cycle in single module" $ do
        let graph = Graph.buildGraph [(mkName "Main", [])]
        Graph.hasCycle graph @?= False,
      testCase "no cycle in linear chain" $ do
        let deps =
              [ (mkName "Main", [mkName "Utils"]),
                (mkName "Utils", [mkName "Base"])
              ]
        let graph = Graph.buildGraph deps
        Graph.hasCycle graph @?= False,
      testCase "detect self-cycle" $ do
        let graph = Graph.addDependency Graph.emptyGraph (mkName "Main") (mkName "Main")
        Graph.hasCycle graph @?= True,
      testCase "detect two-module cycle" $ do
        let deps =
              [ (mkName "A", [mkName "B"]),
                (mkName "B", [mkName "A"])
              ]
        let graph = Graph.buildGraph deps
        Graph.hasCycle graph @?= True,
      testCase "detect three-module cycle" $ do
        let deps =
              [ (mkName "A", [mkName "B"]),
                (mkName "B", [mkName "C"]),
                (mkName "C", [mkName "A"])
              ]
        let graph = Graph.buildGraph deps
        Graph.hasCycle graph @?= True,
      testCase "topological sort returns Nothing for cyclic graph" $ do
        let deps =
              [ (mkName "A", [mkName "B"]),
                (mkName "B", [mkName "A"])
              ]
        let graph = Graph.buildGraph deps
        Graph.topologicalSort graph @?= Nothing
    ]

testDependencyQueries :: TestTree
testDependencyQueries =
  testGroup
    "dependency query tests"
    [ testCase "getModuleDeps for non-existent module" $
        Graph.getModuleDeps Graph.emptyGraph (mkName "NotFound") @?= Nothing,
      testCase "getModuleDeps for module with no deps" $ do
        let graph = Graph.buildGraph [(mkName "Main", [])]
        Graph.getModuleDeps graph (mkName "Main") @?= Just Set.empty,
      testCase "getModuleDeps returns correct deps" $ do
        let deps = [(mkName "Main", [mkName "A", mkName "B"])]
        let graph = Graph.buildGraph deps
        Graph.getModuleDeps graph (mkName "Main")
          @?= Just (Set.fromList [mkName "A", mkName "B"]),
      testCase "transitiveDeps for single level" $ do
        let deps = [(mkName "Main", [mkName "Utils"])]
        let graph = Graph.buildGraph deps
        Set.toList (Graph.transitiveDeps graph (mkName "Main")) @?= [mkName "Utils"],
      testCase "transitiveDeps for multi-level" $ do
        let deps =
              [ (mkName "Main", [mkName "Utils"]),
                (mkName "Utils", [mkName "Base"])
              ]
        let graph = Graph.buildGraph deps
        Graph.transitiveDeps graph (mkName "Main")
          @?= Set.fromList [mkName "Utils", mkName "Base"],
      testCase "transitiveDeps handles shared dependencies" $ do
        let deps =
              [ (mkName "Main", [mkName "A", mkName "B"]),
                (mkName "A", [mkName "Base"]),
                (mkName "B", [mkName "Base"])
              ]
        let graph = Graph.buildGraph deps
        let trans = Graph.transitiveDeps graph (mkName "Main")
        Set.toList trans @?= [mkName "A", mkName "B", mkName "Base"],
      testCase "reverseDeps for module with no dependents" $ do
        let graph = Graph.buildGraph [(mkName "Main", [])]
        Graph.reverseDeps graph (mkName "Main") @?= Just Set.empty,
      testCase "reverseDeps returns correct dependents" $ do
        let deps =
              [ (mkName "Main", [mkName "Utils"]),
                (mkName "App", [mkName "Utils"])
              ]
        let graph = Graph.buildGraph deps
        Graph.reverseDeps graph (mkName "Utils")
          @?= Just (Set.fromList [mkName "Main", mkName "App"])
    ]
