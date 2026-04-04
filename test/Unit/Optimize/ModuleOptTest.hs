{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Optimize.Module.
--
-- Verifies that 'optimize' correctly orchestrates the optimization pipeline
-- for canonical modules. Tests use minimal 'Can.Module' values with empty
-- declarations, unions, aliases, effects, abilities, and impls.
--
-- Because 'optimize' returns a 'Result.Result', tests run it via
-- 'Result.run' and inspect the resulting 'Opt.LocalGraph'.
--
-- == Test Coverage
--
-- * Empty module produces a valid LocalGraph with no nodes
-- * Module with a Normal union: constructor nodes added
-- * Module with an Enum union: enum nodes added
-- * Module with an Unbox union: box node added
-- * Module with a record alias: record constructor node added
-- * Module with a non-record alias: no node added
-- * Module with NoEffects: effects do not change graph
-- * Module with DeriveEncode on a union: encoder node added
-- * Combined unions and aliases produce expected node count
--
-- @since 0.20.0
module Unit.Optimize.ModuleOptTest
  ( tests,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Optimize.Module as Module
import qualified Reporting.Annotation as Ann
import qualified Reporting.Result as Result
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Optimize.Module.
tests :: TestTree
tests =
  Test.testGroup
    "Optimize.Module"
    [ emptyModuleTests,
      normalUnionTests,
      enumUnionTests,
      unboxUnionTests,
      recordAliasTests,
      nonRecordAliasTests,
      noEffectsTests,
      derivingIntegrationTests,
      combinedTests
    ]

-- HELPERS

-- | The test module home name.
testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical Pkg.core (Name.fromChars "Test.Mod")

-- | Run 'optimize' and return the graph on success, or fail.
runOptimize :: Can.Module -> IO Opt.LocalGraph
runOptimize canModule =
  case Result.run (Module.optimize Map.empty canModule) of
    (_, Right graph) -> pure graph
    (_, Left _) -> Test.assertFailure "optimize unexpectedly failed"

-- | Count the number of nodes in a LocalGraph.
nodeCount :: Opt.LocalGraph -> Int
nodeCount (Opt.LocalGraph _ nodes _ _) = Map.size nodes

-- | Check whether a global key exists in the graph.
hasNode :: Opt.Global -> Opt.LocalGraph -> Bool
hasNode g (Opt.LocalGraph _ nodes _ _) = Map.member g nodes

-- | Build a minimal empty Can.Module.
emptyModule :: Can.Module
emptyModule =
  Can.Module
    { Can._name = testHome,
      Can._exports = Can.ExportEverything Ann.one,
      Can._docs = Src.NoDocs Ann.one,
      Can._decls = Can.SaveTheEnvironment,
      Can._unions = Map.empty,
      Can._aliases = Map.empty,
      Can._binops = Map.empty,
      Can._effects = Can.NoEffects,
      Can._lazyImports = Set.empty,
      Can._guards = Map.empty,
      Can._abilities = Map.empty,
      Can._impls = []
    }

-- | Build a module with the given unions substituted in.
moduleWithUnions :: Map.Map Name.Name Can.Union -> Can.Module
moduleWithUnions unions = emptyModule { Can._unions = unions }

-- | Build a module with the given aliases substituted in.
moduleWithAliases :: Map.Map Name.Name Can.Alias -> Can.Module
moduleWithAliases aliases = emptyModule { Can._aliases = aliases }

-- | Build a Normal union with one constructor and no args.
normalUnion :: [Can.DerivingClause] -> Can.Union
normalUnion deriving_ =
  Can.Union [] [] [Can.Ctor (Name.fromChars "Leaf") Index.first 0 []] 1 Can.Normal deriving_

-- | Build an Enum union with two constructors.
enumUnion :: [Can.DerivingClause] -> Can.Union
enumUnion deriving_ =
  Can.Union
    []
    []
    [ Can.Ctor (Name.fromChars "A") Index.first 0 [],
      Can.Ctor (Name.fromChars "B") Index.second 0 []
    ]
    2
    Can.Enum
    deriving_

-- | Build an Unbox union with one constructor and one arg.
unboxUnion :: Can.Union
unboxUnion =
  Can.Union
    []
    []
    [Can.Ctor (Name.fromChars "Wrap") Index.first 1 [Can.TType ModuleName.basics Name.int []]]
    1
    Can.Unbox
    []

-- | Build a record alias with one field.
recordAlias :: Can.Alias
recordAlias =
  Can.Alias
    []
    []
    (Can.TRecord (Map.singleton (Name.fromChars "x") (Can.FieldType 0 (Can.TType ModuleName.basics Name.int []))) Nothing)
    Nothing
    []

-- | Build a non-record alias (e.g. a type synonym).
nonRecordAlias :: Can.Alias
nonRecordAlias =
  Can.Alias
    []
    []
    (Can.TType ModuleName.basics Name.int [])
    Nothing
    []

-- EMPTY MODULE TESTS

-- | An empty module should produce a graph with no nodes.
emptyModuleTests :: TestTree
emptyModuleTests =
  Test.testGroup
    "empty module"
    [ Test.testCase "optimize empty module produces zero nodes" $
        runOptimize emptyModule >>= \g -> nodeCount g @?= 0
    ]

-- NORMAL UNION TESTS

-- | A Normal union should add one Ctor node per constructor.
normalUnionTests :: TestTree
normalUnionTests =
  Test.testGroup
    "Normal union"
    [ Test.testCase "Normal union with one ctor adds one node" $
        let unions = Map.singleton (Name.fromChars "Tree") (normalUnion [])
         in runOptimize (moduleWithUnions unions) >>= \g ->
              nodeCount g @?= 1,
      Test.testCase "Normal union Ctor node is keyed by constructor name" $
        let ctorName = Name.fromChars "Leaf"
            unions = Map.singleton (Name.fromChars "Tree") (normalUnion [])
            ctorGlobal = Opt.Global testHome ctorName
         in runOptimize (moduleWithUnions unions) >>= \g ->
              hasNode ctorGlobal g @?= True
    ]

-- ENUM UNION TESTS

-- | An Enum union should add one Enum node per constructor.
enumUnionTests :: TestTree
enumUnionTests =
  Test.testGroup
    "Enum union"
    [ Test.testCase "Enum union with two ctors adds two nodes" $
        let unions = Map.singleton (Name.fromChars "Dir") (enumUnion [])
         in runOptimize (moduleWithUnions unions) >>= \g ->
              nodeCount g @?= 2,
      Test.testCase "Enum union first ctor node is present" $
        let unions = Map.singleton (Name.fromChars "Dir") (enumUnion [])
            aGlobal = Opt.Global testHome (Name.fromChars "A")
         in runOptimize (moduleWithUnions unions) >>= \g ->
              hasNode aGlobal g @?= True
    ]

-- UNBOX UNION TESTS

-- | An Unbox union should add one Box node for the constructor.
unboxUnionTests :: TestTree
unboxUnionTests =
  Test.testGroup
    "Unbox union"
    [ Test.testCase "Unbox union adds one Box node" $
        let unions = Map.singleton (Name.fromChars "Wrapper") unboxUnion
         in runOptimize (moduleWithUnions unions) >>= \g ->
              nodeCount g @?= 1
    ]

-- RECORD ALIAS TESTS

-- | A record alias should add a constructor function node.
recordAliasTests :: TestTree
recordAliasTests =
  Test.testGroup
    "record alias"
    [ Test.testCase "record alias adds one constructor node" $
        let aliases = Map.singleton (Name.fromChars "Point") recordAlias
         in runOptimize (moduleWithAliases aliases) >>= \g ->
              nodeCount g @?= 1,
      Test.testCase "record alias node is keyed by the alias name" $
        let aliases = Map.singleton (Name.fromChars "Point") recordAlias
            aliasGlobal = Opt.Global testHome (Name.fromChars "Point")
         in runOptimize (moduleWithAliases aliases) >>= \g ->
              hasNode aliasGlobal g @?= True
    ]

-- NON-RECORD ALIAS TESTS

-- | A non-record alias (type synonym) should not add any nodes.
nonRecordAliasTests :: TestTree
nonRecordAliasTests =
  Test.testGroup
    "non-record alias"
    [ Test.testCase "non-record alias adds no nodes" $
        let aliases = Map.singleton (Name.fromChars "Alias") nonRecordAlias
         in runOptimize (moduleWithAliases aliases) >>= \g ->
              nodeCount g @?= 0
    ]

-- NO EFFECTS TESTS

-- | A NoEffects module should not add effect nodes.
noEffectsTests :: TestTree
noEffectsTests =
  Test.testGroup
    "NoEffects"
    [ Test.testCase "module with NoEffects adds no effect nodes" $
        runOptimize emptyModule >>= \g -> nodeCount g @?= 0
    ]

-- DERIVING INTEGRATION TESTS

-- | DeriveEncode on a union should add an encoder node beyond the Ctor node.
derivingIntegrationTests :: TestTree
derivingIntegrationTests =
  Test.testGroup
    "deriving integration"
    [ Test.testCase "DeriveEncode union adds Ctor node plus encoder node" $
        let unions = Map.singleton (Name.fromChars "Status") (enumUnion [Can.DeriveEncode Nothing])
         in runOptimize (moduleWithUnions unions) >>= \g ->
              nodeCount g @?= 3,
      Test.testCase "DeriveEncode encoder node is present in graph" $
        let unions = Map.singleton (Name.fromChars "Status") (enumUnion [Can.DeriveEncode Nothing])
            encodeGlobal = Opt.Global testHome (Name.fromChars "encodeStatus")
         in runOptimize (moduleWithUnions unions) >>= \g ->
              hasNode encodeGlobal g @?= True
    ]

-- COMBINED TESTS

-- | Modules with both unions and aliases should accumulate all nodes.
combinedTests :: TestTree
combinedTests =
  Test.testGroup
    "combined unions and aliases"
    [ Test.testCase "Normal union plus record alias adds two nodes" $
        let canModule = emptyModule
              { Can._unions = Map.singleton (Name.fromChars "Tree") (normalUnion []),
                Can._aliases = Map.singleton (Name.fromChars "Point") recordAlias
              }
         in runOptimize canModule >>= \g ->
              nodeCount g @?= 2
    ]
