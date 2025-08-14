{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Unit.AST.OptimizedTest (tests) where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Kernel as K
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.String as ES
import qualified Data.Index as Index
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Name (Name)
import qualified Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Optimize.DecisionTree as DT
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "AST.Optimized Tests"
    [ testEmptyGlobalGraph
    , testAddGlobalGraph
    , testAddLocalGraph
    , testAddKernel
    , testToKernelGlobal
    , testGlobalEquality
    , testGlobalOrdering
    , testExprConstructors
    , testDefConstructors
    , testPathConstructors
    , testChoiceConstructors
    , testMainConstructors
    , testNodeConstructors
    , testEffectsTypeConstructors
    , testEdgeCases
    ]

-- Test empty GlobalGraph
testEmptyGlobalGraph :: TestTree
testEmptyGlobalGraph =
  testCase "empty creates empty GlobalGraph" $ do
    let graph = Opt.empty
    case graph of
      Opt.GlobalGraph nodes fields ->
        do
          Map.null nodes @?= True
          Map.null fields @?= True

-- Test addGlobalGraph function
testAddGlobalGraph :: TestTree
testAddGlobalGraph =
  testGroup
    "addGlobalGraph"
    [ testCase "combining empty graphs results in empty" $ do
        let result = Opt.addGlobalGraph Opt.empty Opt.empty
        case result of
          Opt.GlobalGraph nodes fields ->
            do
              Map.null nodes @?= True
              Map.null fields @?= True
    , testCase "combining with non-empty graph preserves nodes" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            node1 = Opt.Define (Opt.Bool True) Set.empty
            graph1 = Opt.GlobalGraph (Map.singleton global1 node1) Map.empty
            result = Opt.addGlobalGraph Opt.empty graph1
        case result of
          Opt.GlobalGraph nodes _ ->
            Map.member global1 nodes @?= True
    , testCase "combining two non-empty graphs includes both" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            global2 = Opt.Global ModuleName.basics Name.false
            node1 = Opt.Define (Opt.Bool True) Set.empty
            node2 = Opt.Define (Opt.Bool False) Set.empty
            graph1 = Opt.GlobalGraph (Map.singleton global1 node1) Map.empty
            graph2 = Opt.GlobalGraph (Map.singleton global2 node2) Map.empty
            result = Opt.addGlobalGraph graph1 graph2
        case result of
          Opt.GlobalGraph nodes _ ->
            do
              Map.member global1 nodes @?= True
              Map.member global2 nodes @?= True
    ]

-- Test addLocalGraph function
testAddLocalGraph :: TestTree
testAddLocalGraph =
  testGroup
    "addLocalGraph"
    [ testCase "adding empty local graph to empty global" $ do
        let localGraph = Opt.LocalGraph Nothing Map.empty Map.empty
            result = Opt.addLocalGraph localGraph Opt.empty
        case result of
          Opt.GlobalGraph nodes fields ->
            do
              Map.null nodes @?= True
              Map.null fields @?= True
    , testCase "adding local graph with nodes" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            node1 = Opt.Define (Opt.Bool True) Set.empty
            localGraph =
              Opt.LocalGraph Nothing (Map.singleton global1 node1) Map.empty
            result = Opt.addLocalGraph localGraph Opt.empty
        case result of
          Opt.GlobalGraph nodes _ ->
            Map.member global1 nodes @?= True
    ]

-- Test addKernel function
testAddKernel :: TestTree
testAddKernel =
  testGroup
    "addKernel"
    [ testCase "adding kernel with JS chunk" $ do
        let shortName = Name.fromChars "test"
            chunks = [K.JS "console.log('test')"]
            result = Opt.addKernel shortName chunks Opt.empty
            expectedGlobal = Opt.toKernelGlobal shortName
        case result of
          Opt.GlobalGraph nodes _ ->
            Map.member expectedGlobal nodes @?= True
    , testCase "adding kernel with Canopy variable" $ do
        let shortName = Name.fromChars "test"
            chunks = [K.CanopyVar ModuleName.basics Name.true]
            result = Opt.addKernel shortName chunks Opt.empty
            expectedGlobal = Opt.toKernelGlobal shortName
        case result of
          Opt.GlobalGraph nodes _ ->
            Map.member expectedGlobal nodes @?= True
    ]

-- Test toKernelGlobal function
testToKernelGlobal :: TestTree
testToKernelGlobal =
  testGroup
    "toKernelGlobal"
    [ testCase "creates correct kernel global structure" $ do
        let shortName = Name.fromChars "test"
            result = Opt.toKernelGlobal shortName
        case result of
          Opt.Global moduleName globalName ->
            do
              moduleName @?= ModuleName.Canonical Pkg.kernel shortName
              globalName @?= Name.dollar
    , testCase "different names create different globals" $ do
        let name1 = Name.fromChars "test1"
            name2 = Name.fromChars "test2"
            global1 = Opt.toKernelGlobal name1
            global2 = Opt.toKernelGlobal name2
        global1 /= global2 @?= True
    ]

-- Test Global equality
testGlobalEquality :: TestTree
testGlobalEquality =
  testGroup
    "Global equality"
    [ testCase "same globals are equal" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            global2 = Opt.Global ModuleName.basics Name.true
        global1 == global2 @?= True
    , testCase "different names are not equal" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            global2 = Opt.Global ModuleName.basics Name.false
        global1 == global2 @?= False
    , testCase "different modules are not equal" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            global2 = Opt.Global ModuleName.list Name.true
        global1 == global2 @?= False
    ]

-- Test Global ordering
testGlobalOrdering :: TestTree
testGlobalOrdering =
  testGroup
    "Global ordering"
    [ testCase "ordering by name first" $ do
        let global1 = Opt.Global ModuleName.basics Name.false
            global2 = Opt.Global ModuleName.list Name.true
        compare global1 global2 @?= LT
    , testCase "ordering by module when names equal" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            global2 = Opt.Global ModuleName.list Name.true
        compare global1 global2 @?= LT
    , testCase "equal globals compare as EQ" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            global2 = Opt.Global ModuleName.basics Name.true
        compare global1 global2 @?= EQ
    ]

-- Test Expr constructors
testExprConstructors :: TestTree
testExprConstructors =
  testGroup
    "Expr constructors"
    [ testCase "Bool constructor" $ do
        let expr = Opt.Bool True
        show expr @?= "Bool True"
    , testCase "Int constructor" $ do
        let expr = Opt.Int 42
        show expr @?= "Int 42"
    , testCase "Unit constructor" $ do
        let expr = Opt.Unit
        show expr @?= "Unit"
    , testCase "VarLocal constructor shows correctly" $ do
        let name = Name.fromChars "x"
            expr = Opt.VarLocal name
        -- Just verify it contains the constructor name
        "VarLocal" `elem` words (show expr) @?= True
    , testCase "List constructor with empty list" $ do
        let expr = Opt.List []
        show expr @?= "List []"
    , testCase "List constructor with elements" $ do
        let expr = Opt.List [Opt.Int 1, Opt.Int 2]
        "List" `elem` words (show expr) @?= True
    , testCase "Record constructor with empty map" $ do
        let expr = Opt.Record Map.empty
        "Record" `elem` words (show expr) @?= True
    ]

-- Test Def constructors
testDefConstructors :: TestTree
testDefConstructors =
  testGroup
    "Def constructors"
    [ testCase "Def constructor" $ do
        let name = Name.fromChars "x"
            expr = Opt.Int 42
            def = Opt.Def name expr
        "Def" `elem` words (show def) @?= True
    , testCase "TailDef constructor" $ do
        let name = Name.fromChars "f"
            params = [Name.fromChars "x"]
            expr = Opt.Int 42
            def = Opt.TailDef name params expr
        "TailDef" `elem` words (show def) @?= True
    ]

-- Test Path constructors
testPathConstructors :: TestTree
testPathConstructors =
  testGroup
    "Path constructors"
    [ testCase "Root constructor" $ do
        let name = Name.fromChars "x"
            path = Opt.Root name
        "Root" `elem` words (show path) @?= True
    , testCase "Field constructor" $ do
        let name = Name.fromChars "field"
            root = Opt.Root (Name.fromChars "x")
            path = Opt.Field name root
        "Field" `elem` words (show path) @?= True
    , testCase "Index constructor" $ do
        let index = Index.first
            root = Opt.Root (Name.fromChars "x")
            path = Opt.Index index root
        "Index" `elem` words (show path) @?= True
    , testCase "Unbox constructor" $ do
        let root = Opt.Root (Name.fromChars "x")
            path = Opt.Unbox root
        "Unbox" `elem` words (show path) @?= True
    ]

-- Test Choice constructors
testChoiceConstructors :: TestTree
testChoiceConstructors =
  testGroup
    "Choice constructors"
    [ testCase "Inline constructor" $ do
        let expr = Opt.Bool True
            choice = Opt.Inline expr
        "Inline" `elem` words (show choice) @?= True
    , testCase "Jump constructor" $ do
        let choice = Opt.Jump 42
        show choice @?= "Jump 42"
    ]

-- Test Main constructors
testMainConstructors :: TestTree
testMainConstructors =
  testGroup
    "Main constructors"
    [ testCase "Static constructor" $ do
        let main = Opt.Static
        show main @?= "Static"
    , testCase "Dynamic constructor" $ do
        let message = Can.TUnit
            decoder = Opt.Unit
            main = Opt.Dynamic message decoder
        "Dynamic" `elem` words (show main) @?= True
    ]

-- Test Node constructors
testNodeConstructors :: TestTree
testNodeConstructors =
  testGroup
    "Node constructors"
    [ testCase "Define constructor" $ do
        let expr = Opt.Bool True
            deps = Set.empty
            node = Opt.Define expr deps
        "Define" `elem` words (show node) @?= True
    , testCase "Box constructor" $ do
        let node = Opt.Box
        show node @?= "Box"
    , testCase "Enum constructor" $ do
        let index = Index.first
            node = Opt.Enum index
        "Enum" `elem` words (show node) @?= True
    , testCase "Manager constructor" $ do
        let effectsType = Opt.Cmd
            node = Opt.Manager effectsType
        "Manager" `elem` words (show node) @?= True
    ]

-- Test EffectsType constructors
testEffectsTypeConstructors :: TestTree
testEffectsTypeConstructors =
  testGroup
    "EffectsType constructors"
    [ testCase "Cmd constructor" $ do
        let effectsType = Opt.Cmd
        show effectsType @?= "Cmd"
    , testCase "Sub constructor" $ do
        let effectsType = Opt.Sub
        show effectsType @?= "Sub"
    , testCase "Fx constructor" $ do
        let effectsType = Opt.Fx
        show effectsType @?= "Fx"
    ]

-- Test edge cases
testEdgeCases :: TestTree
testEdgeCases =
  testGroup
    "Edge cases"
    [ testCase "deeply nested expressions" $ do
        let deepExpr =
              Opt.Let
                (Opt.Def (Name.fromChars "x") (Opt.Int 1))
                ( Opt.Let
                    (Opt.Def (Name.fromChars "y") (Opt.Int 2))
                    (Opt.VarLocal (Name.fromChars "x"))
                )
        "Let" `elem` words (show deepExpr) @?= True
    , testCase "large integer values" $ do
        let expr = Opt.Int maxBound
        show expr @?= "Int " ++ show (maxBound :: Int)
    , testCase "negative integer values" $ do
        let expr = Opt.Int minBound
        show expr @?= "Int (" ++ show (minBound :: Int) ++ ")"
    , testCase "empty string handling" $ do
        let emptyStr = ES.fromChunks []
            expr = Opt.Str emptyStr
        "Str" `elem` words (show expr) @?= True
    , testCase "complex tuple with all slots" $ do
        let tuple = Opt.Tuple (Opt.Int 1) (Opt.Int 2) (Just (Opt.Int 3))
        "Tuple" `elem` words (show tuple) @?= True
    , testCase "tuple with only two elements" $ do
        let tuple = Opt.Tuple (Opt.Int 1) (Opt.Int 2) Nothing
        "Tuple" `elem` words (show tuple) @?= True
    ]