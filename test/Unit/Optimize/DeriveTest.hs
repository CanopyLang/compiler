{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Optimize.Derive.
--
-- Verifies that 'addDerivedDefs' correctly adds generated encoder, decoder,
-- and enum-list definitions to the optimization graph for types annotated
-- with @deriving@ clauses, and leaves the graph unchanged when no applicable
-- derivations are present.
--
-- == Test Coverage
--
-- * Empty unions and aliases map: graph unchanged
-- * Union with no deriving clauses: graph unchanged
-- * Union with DeriveOrd only: graph unchanged (Ord has no generated function)
-- * Union with DeriveEncode: encoder node added to graph
-- * Union with DeriveDecode: decoder node added to graph
-- * Union with DeriveEnum: allTypeName list node added to graph
-- * Alias with DeriveEncode for record type: encoder node added
-- * Alias with DeriveDecode for record type: decoder node added
-- * Alias with type params and DeriveEncode: skipped (not supported)
--
-- @since 0.20.0
module Unit.Optimize.DeriveTest
  ( tests,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import qualified Data.Set as Set
import qualified Optimize.Derive as Derive
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Optimize.Derive.
tests :: TestTree
tests =
  Test.testGroup
    "Optimize.Derive"
    [ emptyInputTests,
      unionNoDeriveTests,
      unionDeriveOrdTests,
      unionDeriveEncodeTests,
      unionDeriveDecodeTests,
      unionDeriveEnumTests,
      aliasNoDeriveTests,
      aliasWithTypeParamsTests,
      aliasDeriveEncodeTests,
      aliasDeriveDecodeTests
    ]

-- HELPERS

-- | A test module home for use in all tests.
testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical Pkg.core (Name.fromChars "Test.Module")

-- | An empty local graph to use as a starting point.
emptyGraph :: Opt.LocalGraph
emptyGraph = Opt.LocalGraph Nothing Map.empty Map.empty Map.empty

-- | Count the nodes in a local graph.
nodeCount :: Opt.LocalGraph -> Int
nodeCount (Opt.LocalGraph _ nodes _ _) = Map.size nodes

-- | Retrieve a node by its global key from a local graph.
lookupNode :: Opt.Global -> Opt.LocalGraph -> Maybe Opt.Node
lookupNode g (Opt.LocalGraph _ nodes _ _) = Map.lookup g nodes

-- | Build a minimal enum union (no args, multiple constructors).
mkEnumUnion :: [Name.Name] -> [Can.DerivingClause] -> Can.Union
mkEnumUnion ctorNames deriving_ =
  Can.Union
    []
    []
    (zipWith mkEnumCtor ctorNames [0 ..])
    (length ctorNames)
    Can.Enum
    deriving_

-- | Build a ZeroBased index from a raw Int by iterating from 'Index.first'.
mkZeroBased :: Int -> Index.ZeroBased
mkZeroBased n = iterate Index.next Index.first !! n

mkEnumCtor :: Name.Name -> Int -> Can.Ctor
mkEnumCtor name idx = Can.Ctor name (mkZeroBased idx) 0 []

-- | Build a minimal normal union with one constructor and no args.
mkNormalUnion :: [Can.DerivingClause] -> Can.Union
mkNormalUnion deriving_ =
  Can.Union
    []
    []
    [Can.Ctor (Name.fromChars "Leaf") Index.first 0 []]
    1
    Can.Normal
    deriving_

-- | Build a record alias with the given fields and deriving list.
mkRecordAlias :: [(Name.Name, Can.Type)] -> [Can.DerivingClause] -> Can.Alias
mkRecordAlias fieldPairs deriving_ =
  Can.Alias
    []
    []
    (Can.TRecord (Map.fromList (fmap mkField fieldPairs)) Nothing)
    Nothing
    deriving_
  where
    mkField (n, t) = (n, Can.FieldType 0 t)

-- | Build a polymorphic alias with a type parameter.
mkPolyAlias :: [Can.DerivingClause] -> Can.Alias
mkPolyAlias deriving_ =
  Can.Alias
    [Name.fromChars "a"]
    [Can.Invariant]
    (Can.TType testHome (Name.fromChars "MyType") [Can.TVar (Name.fromChars "a")])
    Nothing
    deriving_

-- EMPTY INPUT TESTS

-- | Empty union and alias maps leave the graph unchanged.
emptyInputTests :: TestTree
emptyInputTests =
  Test.testGroup
    "empty inputs"
    [ Test.testCase "empty unions and aliases: graph unchanged" $
        nodeCount (Derive.addDerivedDefs testHome Map.empty Map.empty emptyGraph)
          @?= nodeCount emptyGraph
    ]

-- UNION WITH NO DERIVING

-- | A union with no deriving clauses should not add any nodes.
unionNoDeriveTests :: TestTree
unionNoDeriveTests =
  Test.testGroup
    "union with no deriving"
    [ Test.testCase "union with empty deriving list: graph unchanged" $
        let unions = Map.singleton (Name.fromChars "Color") (mkEnumUnion [Name.fromChars "Red"] [])
         in nodeCount (Derive.addDerivedDefs testHome unions Map.empty emptyGraph)
              @?= 0
    ]

-- UNION WITH DERIVEORD ONLY

-- | DeriveOrd produces no generated function.
unionDeriveOrdTests :: TestTree
unionDeriveOrdTests =
  Test.testGroup
    "union with DeriveOrd only"
    [ Test.testCase "DeriveOrd does not add nodes to graph" $
        let unions = Map.singleton (Name.fromChars "Status") (mkNormalUnion [Can.DeriveOrd])
         in nodeCount (Derive.addDerivedDefs testHome unions Map.empty emptyGraph)
              @?= 0
    ]

-- UNION WITH DERIVEENCODE

-- | DeriveEncode should add an @encodeTypeName@ node.
unionDeriveEncodeTests :: TestTree
unionDeriveEncodeTests =
  Test.testGroup
    "union with DeriveEncode"
    [ Test.testCase "DeriveEncode adds one node to graph" $
        let unions = Map.singleton (Name.fromChars "Color") (mkEnumUnion [Name.fromChars "Red"] [Can.DeriveEncode Nothing])
            result = Derive.addDerivedDefs testHome unions Map.empty emptyGraph
         in nodeCount result @?= 1,
      Test.testCase "DeriveEncode node is keyed as encodeTypeName global" $
        let typeName = Name.fromChars "Color"
            unions = Map.singleton typeName (mkEnumUnion [Name.fromChars "Red"] [Can.DeriveEncode Nothing])
            result = Derive.addDerivedDefs testHome unions Map.empty emptyGraph
            encodeKey = Opt.Global testHome (Name.fromChars "encodeColor")
         in Test.assertBool "encode node should exist in graph" (isJust (lookupNode encodeKey result))
    ]

-- UNION WITH DERIVEDECODE

-- | DeriveDecode should add a @typeNameDecoder@ node.
unionDeriveDecodeTests :: TestTree
unionDeriveDecodeTests =
  Test.testGroup
    "union with DeriveDecode"
    [ Test.testCase "DeriveDecode adds one node to graph" $
        let unions = Map.singleton (Name.fromChars "Color") (mkEnumUnion [Name.fromChars "Red"] [Can.DeriveDecode Nothing])
            result = Derive.addDerivedDefs testHome unions Map.empty emptyGraph
         in nodeCount result @?= 1,
      Test.testCase "DeriveDecode node is keyed as typeNameDecoder global" $
        let typeName = Name.fromChars "Color"
            unions = Map.singleton typeName (mkEnumUnion [Name.fromChars "Red"] [Can.DeriveDecode Nothing])
            result = Derive.addDerivedDefs testHome unions Map.empty emptyGraph
            decodeKey = Opt.Global testHome (Name.fromChars "colorDecoder")
         in Test.assertBool "decode node should exist in graph" (isJust (lookupNode decodeKey result))
    ]

-- UNION WITH DERIVEENUM

-- | DeriveEnum should add an @allTypeName@ list node.
unionDeriveEnumTests :: TestTree
unionDeriveEnumTests =
  Test.testGroup
    "union with DeriveEnum"
    [ Test.testCase "DeriveEnum adds one node to graph" $
        let unions = Map.singleton (Name.fromChars "Status") (mkEnumUnion [Name.fromChars "Active", Name.fromChars "Inactive"] [Can.DeriveEnum])
            result = Derive.addDerivedDefs testHome unions Map.empty emptyGraph
         in nodeCount result @?= 1,
      Test.testCase "DeriveEnum node is keyed as allTypeName global" $
        let typeName = Name.fromChars "Status"
            unions = Map.singleton typeName (mkEnumUnion [Name.fromChars "Active"] [Can.DeriveEnum])
            result = Derive.addDerivedDefs testHome unions Map.empty emptyGraph
            enumKey = Opt.Global testHome (Name.fromChars "allStatus")
         in Test.assertBool "enum node should exist in graph" (isJust (lookupNode enumKey result))
    ]

-- ALIAS WITH NO DERIVING

-- | An alias with an empty deriving list should not add nodes.
aliasNoDeriveTests :: TestTree
aliasNoDeriveTests =
  Test.testGroup
    "alias with no deriving"
    [ Test.testCase "record alias with empty deriving: graph unchanged" $
        let aliases = Map.singleton (Name.fromChars "Point") (mkRecordAlias [(Name.fromChars "x", Can.TType ModuleName.basics Name.int [])] [])
         in nodeCount (Derive.addDerivedDefs testHome Map.empty aliases emptyGraph)
              @?= 0
    ]

-- ALIAS WITH TYPE PARAMS (SKIPPED)

-- | Aliases with type parameters are skipped for Encode and Decode derivation.
aliasWithTypeParamsTests :: TestTree
aliasWithTypeParamsTests =
  Test.testGroup
    "alias with type params"
    [ Test.testCase "polymorphic alias DeriveEncode is skipped: no nodes added" $
        let aliases = Map.singleton (Name.fromChars "Wrapper") (mkPolyAlias [Can.DeriveEncode Nothing])
         in nodeCount (Derive.addDerivedDefs testHome Map.empty aliases emptyGraph)
              @?= 0,
      Test.testCase "polymorphic alias DeriveDecode is skipped: no nodes added" $
        let aliases = Map.singleton (Name.fromChars "Wrapper") (mkPolyAlias [Can.DeriveDecode Nothing])
         in nodeCount (Derive.addDerivedDefs testHome Map.empty aliases emptyGraph)
              @?= 0
    ]

-- ALIAS DERIVEENCODE

-- | Record aliases with DeriveEncode should add an encoder node.
aliasDeriveEncodeTests :: TestTree
aliasDeriveEncodeTests =
  Test.testGroup
    "record alias with DeriveEncode"
    [ Test.testCase "DeriveEncode on record alias adds one node" $
        let fields = [(Name.fromChars "x", Can.TType ModuleName.basics Name.int [])]
            aliases = Map.singleton (Name.fromChars "Point") (mkRecordAlias fields [Can.DeriveEncode Nothing])
            result = Derive.addDerivedDefs testHome Map.empty aliases emptyGraph
         in nodeCount result @?= 1,
      Test.testCase "DeriveEncode on record alias node keyed as encodeTypeName" $
        let fields = [(Name.fromChars "x", Can.TType ModuleName.basics Name.int [])]
            aliases = Map.singleton (Name.fromChars "Point") (mkRecordAlias fields [Can.DeriveEncode Nothing])
            result = Derive.addDerivedDefs testHome Map.empty aliases emptyGraph
            encodeKey = Opt.Global testHome (Name.fromChars "encodePoint")
         in Test.assertBool "encode node should exist in graph" (isJust (lookupNode encodeKey result))
    ]

-- ALIAS DERIVEDECODE

-- | Record aliases with DeriveDecode should add a decoder node.
aliasDeriveDecodeTests :: TestTree
aliasDeriveDecodeTests =
  Test.testGroup
    "record alias with DeriveDecode"
    [ Test.testCase "DeriveDecode on record alias adds one node" $
        let fields = [(Name.fromChars "x", Can.TType ModuleName.basics Name.int [])]
            aliases = Map.singleton (Name.fromChars "Point") (mkRecordAlias fields [Can.DeriveDecode Nothing])
            result = Derive.addDerivedDefs testHome Map.empty aliases emptyGraph
         in nodeCount result @?= 1,
      Test.testCase "DeriveDecode on record alias node keyed as typeNameDecoder" $
        let fields = [(Name.fromChars "x", Can.TType ModuleName.basics Name.int [])]
            aliases = Map.singleton (Name.fromChars "Point") (mkRecordAlias fields [Can.DeriveDecode Nothing])
            result = Derive.addDerivedDefs testHome Map.empty aliases emptyGraph
            decodeKey = Opt.Global testHome (Name.fromChars "pointDecoder")
         in Test.assertBool "decode node should exist in graph" (isJust (lookupNode decodeKey result))
    ]
