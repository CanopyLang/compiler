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
import Data.Maybe (isJust)
import Data.Name (Name)
import qualified Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Optimize.DecisionTree as DT
import Test.Tasty
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "AST.Optimized Tests"
    [ testEmptyGlobalGraph,
      testAddGlobalGraph,
      testAddLocalGraph,
      testAddKernel,
      testToKernelGlobal,
      testGlobalEquality,
      testGlobalOrdering,
      testExprConstructors,
      testDefConstructors,
      testPathConstructors,
      testChoiceConstructors,
      testMainConstructors,
      testNodeConstructors,
      testEffectsTypeConstructors,
      testEdgeCases
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
              Map.null fields @?= True,
      testCase "combining with non-empty graph preserves nodes" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            node1 = Opt.Define (Opt.Bool True) Set.empty
            graph1 = Opt.GlobalGraph (Map.singleton global1 node1) Map.empty
            result = Opt.addGlobalGraph Opt.empty graph1
        case result of
          Opt.GlobalGraph nodes _ ->
            Map.member global1 nodes @?= True,
      testCase "combining two non-empty graphs includes both" $ do
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
              Map.null fields @?= True,
      testCase "adding local graph with nodes" $ do
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
            Map.member expectedGlobal nodes @?= True,
      testCase "adding kernel with Canopy variable" $ do
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
              globalName @?= Name.dollar,
      testCase "different names create different globals" $ do
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
        global1 == global2 @?= True,
      testCase "different names are not equal" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            global2 = Opt.Global ModuleName.basics Name.false
        global1 == global2 @?= False,
      testCase "different modules are not equal" $ do
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
        compare global1 global2 @?= LT,
      testCase "ordering by module when names equal" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            global2 = Opt.Global ModuleName.list Name.true
        compare global1 global2 @?= LT,
      testCase "equal globals compare as EQ" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            global2 = Opt.Global ModuleName.basics Name.true
        compare global1 global2 @?= EQ
    ]

-- Test Expr constructors
testExprConstructors :: TestTree
testExprConstructors =
  testGroup
    "Expr constructors"
    [ testCase "Bool constructor creates correct boolean expression" $ do
        let exprTrue = Opt.Bool True
            exprFalse = Opt.Bool False
        -- Test that we can extract the boolean value
        extractBoolValue exprTrue @?= Just True
        extractBoolValue exprFalse @?= Just False
        extractBoolValue (Opt.Int 42) @?= Nothing,
      testCase "Int constructor creates correct integer expression" $ do
        let expr42 = Opt.Int 42
            expr0 = Opt.Int 0
            exprNeg = Opt.Int (-5)
        -- Test that we can extract the integer value
        extractIntValue expr42 @?= Just 42
        extractIntValue expr0 @?= Just 0
        extractIntValue exprNeg @?= Just (-5)
        extractIntValue (Opt.Bool True) @?= Nothing,
      testCase "Unit constructor represents unit value" $ do
        let expr = Opt.Unit
        -- Test that unit expressions are recognized
        isUnitExpression expr @?= True
        isUnitExpression (Opt.Bool True) @?= False
        isUnitExpression (Opt.Int 0) @?= False,
      testCase "VarLocal constructor creates local variable reference" $ do
        let name = Name.fromChars "x"
            expr = Opt.VarLocal name
        -- Test that we can extract variable name and it's local
        extractLocalVarName expr @?= Just name
        extractLocalVarName (Opt.Bool True) @?= Nothing
        isLocalVariable expr @?= True,
      testCase "List constructor creates list expressions" $ do
        let emptyList = Opt.List []
            intList = Opt.List [Opt.Int 1, Opt.Int 2]
            mixedList = Opt.List [Opt.Int 1, Opt.Bool True]
        -- Test list structure and contents
        getListLength emptyList @?= Just 0
        getListLength intList @?= Just 2
        getListLength mixedList @?= Just 2
        getListLength (Opt.Int 42) @?= Nothing
        isEmptyList emptyList @?= True
        isEmptyList intList @?= False,
      testCase "Record constructor creates record expressions" $ do
        let emptyRecord = Opt.Record Map.empty
            singleField = Opt.Record (Map.singleton (Name.fromChars "x") (Opt.Int 42))
        -- Test record structure
        getRecordFieldCount emptyRecord @?= 0
        getRecordFieldCount singleField @?= 1
        hasRecordField (Name.fromChars "x") singleField @?= True
        hasRecordField (Name.fromChars "y") singleField @?= False
    ]

-- Test Def constructors
testDefConstructors :: TestTree
testDefConstructors =
  testGroup
    "Def constructors"
    [ testCase "Def constructor creates simple definition" $ do
        let name = Name.fromChars "x"
            expr = Opt.Int 42
            def = Opt.Def name expr
        -- Test definition structure and properties
        getDefName def @?= name
        isTailDef def @?= False
        -- Test that we can recognize non-tail definitions
        case def of
          Opt.Def n e -> do
            n @?= name
            extractIntValue e @?= Just 42
          _ -> assertFailure "Expected Def constructor",
      testCase "TailDef constructor creates tail-recursive definition" $ do
        let name = Name.fromChars "f"
            params = [Name.fromChars "x"]
            expr = Opt.Int 42
            def = Opt.TailDef name params expr
        -- Test tail definition structure
        getDefName def @?= name
        isTailDef def @?= True
        -- Test parameter handling
        case def of
          Opt.TailDef n ps e -> do
            n @?= name
            length ps @?= 1
            head ps @?= Name.fromChars "x"
            extractIntValue e @?= Just 42
          _ -> assertFailure "Expected TailDef constructor"
    ]

-- Test Path constructors
testPathConstructors :: TestTree
testPathConstructors =
  testGroup
    "Path constructors"
    [ testCase "Root constructor creates base path" $ do
        let name = Name.fromChars "x"
            path = Opt.Root name
        -- Test path structure and traversal
        isRootPath path @?= True
        isFieldPath path @?= False
        isIndexPath path @?= False
        isUnboxPath path @?= False
        getPathRootName path @?= Just name,
      testCase "Field constructor creates field access path" $ do
        let fieldName = Name.fromChars "field"
            root = Opt.Root (Name.fromChars "x")
            path = Opt.Field fieldName root
        -- Test field path properties
        isFieldPath path @?= True
        isRootPath path @?= False
        getPathRootName path @?= Just (Name.fromChars "x")
        case path of
          Opt.Field name innerPath -> do
            name @?= fieldName
            isRootPath innerPath @?= True
          _ -> assertFailure "Expected Field constructor",
      testCase "Index constructor creates indexed access path" $ do
        let index = Index.first
            root = Opt.Root (Name.fromChars "x")
            path = Opt.Index index root
        -- Test index path properties
        isIndexPath path @?= True
        isRootPath path @?= False
        getPathRootName path @?= Just (Name.fromChars "x")
        case path of
          Opt.Index idx innerPath -> do
            idx @?= index
            isRootPath innerPath @?= True
          _ -> assertFailure "Expected Index constructor",
      testCase "Unbox constructor creates unboxing path" $ do
        let root = Opt.Root (Name.fromChars "x")
            path = Opt.Unbox root
        -- Test unbox path properties
        isUnboxPath path @?= True
        isRootPath path @?= False
        getPathRootName path @?= Just (Name.fromChars "x")
        case path of
          Opt.Unbox innerPath -> do
            isRootPath innerPath @?= True
          _ -> assertFailure "Expected Unbox constructor"
    ]

-- Test Choice constructors
testChoiceConstructors :: TestTree
testChoiceConstructors =
  testGroup
    "Choice constructors"
    [ testCase "Inline constructor embeds expression directly" $ do
        let expr = Opt.Bool True
            choice = Opt.Inline expr
        -- Test choice type and embedded expression
        isInlineChoice choice @?= True
        isJumpChoice choice @?= False
        case choice of
          Opt.Inline e -> extractBoolValue e @?= Just True
          _ -> assertFailure "Expected Inline constructor",
      testCase "Jump constructor creates jump to target" $ do
        let targetId = 42
            choice = Opt.Jump targetId
        -- Test jump choice properties
        isJumpChoice choice @?= True
        isInlineChoice choice @?= False
        case choice of
          Opt.Jump id -> id @?= targetId
          _ -> assertFailure "Expected Jump constructor"
    ]

-- Test Main constructors
testMainConstructors :: TestTree
testMainConstructors =
  testGroup
    "Main constructors"
    [ testCase "Static constructor creates static main" $ do
        let main = Opt.Static
        -- Test main type properties
        isStaticMain main @?= True
        isDynamicMain main @?= False,
      testCase "Dynamic constructor creates dynamic main with message and decoder" $ do
        let message = Can.TUnit
            decoder = Opt.Unit
            main = Opt.Dynamic message decoder
        -- Test dynamic main properties
        isDynamicMain main @?= True
        isStaticMain main @?= False
        case main of
          Opt.Dynamic msg dec -> do
            msg @?= Can.TUnit
            isUnitExpression dec @?= True
          _ -> assertFailure "Expected Dynamic constructor"
    ]

-- Test Node constructors
testNodeConstructors :: TestTree
testNodeConstructors =
  testGroup
    "Node constructors"
    [ testCase "Define constructor creates definition node with dependencies" $ do
        let expr = Opt.Bool True
            deps = Set.empty
            node = Opt.Define expr deps
        -- Test node type and structure
        isDefineNode node @?= True
        isBoxNode node @?= False
        isEnumNode node @?= False
        isManagerNode node @?= False
        case node of
          Opt.Define e d -> do
            extractBoolValue e @?= Just True
            Set.null d @?= True
          _ -> assertFailure "Expected Define constructor",
      testCase "Box constructor creates boxing node" $ do
        let node = Opt.Box
        -- Test box node properties
        isBoxNode node @?= True
        isDefineNode node @?= False
        isEnumNode node @?= False
        isManagerNode node @?= False,
      testCase "Enum constructor creates enumeration node" $ do
        let index = Index.first
            node = Opt.Enum index
        -- Test enum node properties
        isEnumNode node @?= True
        isBoxNode node @?= False
        case node of
          Opt.Enum idx -> idx @?= index
          _ -> assertFailure "Expected Enum constructor",
      testCase "Manager constructor creates effects manager node" $ do
        let effectsType = Opt.Cmd
            node = Opt.Manager effectsType
        -- Test manager node properties
        isManagerNode node @?= True
        isBoxNode node @?= False
        case node of
          Opt.Manager eff -> isCmdEffect eff @?= True
          _ -> assertFailure "Expected Manager constructor"
    ]

-- Test EffectsType constructors
testEffectsTypeConstructors :: TestTree
testEffectsTypeConstructors =
  testGroup
    "EffectsType constructors"
    [ testCase "Cmd constructor creates command effects type" $ do
        let effectsType = Opt.Cmd
        -- Test effects type classification
        isCmdEffect effectsType @?= True
        isSubEffect effectsType @?= False
        isFxEffect effectsType @?= False,
      testCase "Sub constructor creates subscription effects type" $ do
        let effectsType = Opt.Sub
        -- Test effects type classification
        isSubEffect effectsType @?= True
        isCmdEffect effectsType @?= False
        isFxEffect effectsType @?= False,
      testCase "Fx constructor creates general effects type" $ do
        let effectsType = Opt.Fx
        -- Test effects type classification
        isFxEffect effectsType @?= True
        isCmdEffect effectsType @?= False
        isSubEffect effectsType @?= False
    ]

-- Test edge cases
testEdgeCases :: TestTree
testEdgeCases =
  testGroup
    "Edge cases"
    [ testCase "deeply nested expressions preserve structure" $ do
        let deepExpr =
              Opt.Let
                (Opt.Def (Name.fromChars "x") (Opt.Int 1))
                ( Opt.Let
                    (Opt.Def (Name.fromChars "y") (Opt.Int 2))
                    (Opt.VarLocal (Name.fromChars "x"))
                )
        -- Test nested structure can be traversed correctly
        case deepExpr of
          Opt.Let outerDef innerExpr -> do
            getDefName outerDef @?= Name.fromChars "x"
            case innerExpr of
              Opt.Let innerDef finalExpr -> do
                getDefName innerDef @?= Name.fromChars "y"
                extractLocalVarName finalExpr @?= Just (Name.fromChars "x")
              _ -> assertFailure "Expected nested Let expression"
          _ -> assertFailure "Expected Let expression",
      testCase "large integer values are preserved correctly" $ do
        let expr = Opt.Int maxBound
        -- Test that large integers are handled correctly
        extractIntValue expr @?= Just maxBound
        case expr of
          Opt.Int val -> val @?= maxBound
          _ -> assertFailure "Expected Int expression",
      testCase "negative integer values are preserved correctly" $ do
        let expr = Opt.Int minBound
        -- Test that negative integers are handled correctly
        extractIntValue expr @?= Just minBound
        case expr of
          Opt.Int val -> val @?= minBound
          _ -> assertFailure "Expected Int expression",
      testCase "empty string expressions are handled correctly" $ do
        let emptyStr = ES.fromChunks []
            expr = Opt.Str emptyStr
        -- Test string expression structure
        case expr of
          Opt.Str str -> str @?= emptyStr
          _ -> assertFailure "Expected Str expression",
      testCase "complex tuple with all slots" $ do
        let tuple = Opt.Tuple (Opt.Int 1) (Opt.Int 2) (Just (Opt.Int 3))
        -- Test tuple structure and accessing components
        getTupleSize tuple @?= 3
        extractIntValue (getTupleFirst tuple) @?= Just 1
        extractIntValue (getTupleSecond tuple) @?= Just 2
        case getTupleThird tuple of
          Just thirdExpr -> extractIntValue thirdExpr @?= Just 3
          Nothing -> assertFailure "Expected third element in 3-tuple",
      testCase "tuple with only two elements" $ do
        let tuple = Opt.Tuple (Opt.Int 1) (Opt.Int 2) Nothing
        -- Test tuple structure and accessing components
        getTupleSize tuple @?= 2
        extractIntValue (getTupleFirst tuple) @?= Just 1
        extractIntValue (getTupleSecond tuple) @?= Just 2
        isJust (getTupleThird tuple) @?= False -- 2-tuple should not have third element
    ]

-- Helper functions for testing actual AST behavior instead of Show instances

-- Extract boolean value from Bool expressions
extractBoolValue :: Opt.Expr -> Maybe Bool
extractBoolValue (Opt.Bool b) = Just b
extractBoolValue _ = Nothing

-- Extract integer value from Int expressions
extractIntValue :: Opt.Expr -> Maybe Int
extractIntValue (Opt.Int i) = Just i
extractIntValue _ = Nothing

-- Check if expression is Unit
isUnitExpression :: Opt.Expr -> Bool
isUnitExpression Opt.Unit = True
isUnitExpression _ = False

-- Extract local variable name
extractLocalVarName :: Opt.Expr -> Maybe Name
extractLocalVarName (Opt.VarLocal name) = Just name
extractLocalVarName _ = Nothing

-- Check if expression is a local variable
isLocalVariable :: Opt.Expr -> Bool
isLocalVariable (Opt.VarLocal _) = True
isLocalVariable _ = False

-- Get list length
getListLength :: Opt.Expr -> Maybe Int
getListLength (Opt.List items) = Just (length items)
getListLength _ = Nothing

-- Check if list is empty
isEmptyList :: Opt.Expr -> Bool
isEmptyList (Opt.List []) = True
isEmptyList _ = False

-- Get record field count
getRecordFieldCount :: Opt.Expr -> Int
getRecordFieldCount (Opt.Record fields) = Map.size fields
getRecordFieldCount _ = 0

-- Check if record has field
hasRecordField :: Name -> Opt.Expr -> Bool
hasRecordField name (Opt.Record fields) = Map.member name fields
hasRecordField _ _ = False

-- Get tuple size
getTupleSize :: Opt.Expr -> Int
getTupleSize (Opt.Tuple _ _ Nothing) = 2
getTupleSize (Opt.Tuple _ _ (Just _)) = 3
getTupleSize _ = 0

-- Get tuple components (avoiding Eq comparisons by using helper functions)
getTupleFirst :: Opt.Expr -> Opt.Expr
getTupleFirst (Opt.Tuple first _ _) = first
getTupleFirst _ = Opt.Unit -- Default fallback

getTupleSecond :: Opt.Expr -> Opt.Expr
getTupleSecond (Opt.Tuple _ second _) = second
getTupleSecond _ = Opt.Unit -- Default fallback

getTupleThird :: Opt.Expr -> Maybe Opt.Expr
getTupleThird (Opt.Tuple _ _ third) = third
getTupleThird _ = Nothing

-- Additional helper to check tuple component types without direct comparison
getTupleFirstInt :: Opt.Expr -> Maybe Int
getTupleFirstInt expr = extractIntValue (getTupleFirst expr)

getTupleSecondInt :: Opt.Expr -> Maybe Int
getTupleSecondInt expr = extractIntValue (getTupleSecond expr)

getTupleThirdInt :: Opt.Expr -> Maybe Int
getTupleThirdInt expr = case getTupleThird expr of
  Just thirdExpr -> extractIntValue thirdExpr
  Nothing -> Nothing

-- Extract definition name
getDefName :: Opt.Def -> Name
getDefName (Opt.Def name _) = name
getDefName (Opt.TailDef name _ _) = name

-- Check if definition is tail-recursive
isTailDef :: Opt.Def -> Bool
isTailDef (Opt.TailDef _ _ _) = True
isTailDef _ = False

-- Get path root name
getPathRootName :: Opt.Path -> Maybe Name
getPathRootName (Opt.Root name) = Just name
getPathRootName (Opt.Field _ path) = getPathRootName path
getPathRootName (Opt.Index _ path) = getPathRootName path
getPathRootName (Opt.Unbox path) = getPathRootName path

-- Check path type
isRootPath :: Opt.Path -> Bool
isRootPath (Opt.Root _) = True
isRootPath _ = False

isFieldPath :: Opt.Path -> Bool
isFieldPath (Opt.Field _ _) = True
isFieldPath _ = False

isIndexPath :: Opt.Path -> Bool
isIndexPath (Opt.Index _ _) = True
isIndexPath _ = False

isUnboxPath :: Opt.Path -> Bool
isUnboxPath (Opt.Unbox _) = True
isUnboxPath _ = False

-- Choice type checking
isInlineChoice :: Opt.Choice -> Bool
isInlineChoice (Opt.Inline _) = True
isInlineChoice _ = False

isJumpChoice :: Opt.Choice -> Bool
isJumpChoice (Opt.Jump _) = True
isJumpChoice _ = False

-- Main type checking
isStaticMain :: Opt.Main -> Bool
isStaticMain Opt.Static = True
isStaticMain _ = False

isDynamicMain :: Opt.Main -> Bool
isDynamicMain (Opt.Dynamic _ _) = True
isDynamicMain _ = False

-- Node type checking
isDefineNode :: Opt.Node -> Bool
isDefineNode (Opt.Define _ _) = True
isDefineNode _ = False

isBoxNode :: Opt.Node -> Bool
isBoxNode Opt.Box = True
isBoxNode _ = False

isEnumNode :: Opt.Node -> Bool
isEnumNode (Opt.Enum _) = True
isEnumNode _ = False

isManagerNode :: Opt.Node -> Bool
isManagerNode (Opt.Manager _) = True
isManagerNode _ = False

-- Effects type checking
isCmdEffect :: Opt.EffectsType -> Bool
isCmdEffect Opt.Cmd = True
isCmdEffect _ = False

isSubEffect :: Opt.EffectsType -> Bool
isSubEffect Opt.Sub = True
isSubEffect _ = False

isFxEffect :: Opt.EffectsType -> Bool
isFxEffect Opt.Fx = True
isFxEffect _ = False
