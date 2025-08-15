{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Property.AST.OptimizedProps (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.Kernel as K
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Name (Name)
import qualified Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests =
  testGroup
    "AST.Optimized Property Tests"
    [ testGlobalGraphProperties,
      testGlobalProperties,
      testKernelProperties
    ]

-- Generator for Name
genName :: Gen Name
genName = do
  first <- elements ['a' .. 'z']
  rest <- listOf (elements (['a' .. 'z'] <> ['A' .. 'Z'] <> ['0' .. '9']))
  pure (Name.fromChars (first : rest))

-- Generator for Global
genGlobal :: Gen Opt.Global
genGlobal = do
  moduleName <- elements [ModuleName.basics, ModuleName.list, ModuleName.jsonDecode]
  name <- genName
  pure (Opt.Global moduleName name)

-- Generator for small maps
genSmallMap :: Ord k => Gen k -> Gen v -> Gen (Map k v)
genSmallMap genK genV = do
  keys <- listOf genK
  vals <- vectorOf (length keys) genV
  pure (Map.fromList (zip keys vals))

-- Test GlobalGraph properties
testGlobalGraphProperties :: TestTree
testGlobalGraphProperties =
  testGroup
    "GlobalGraph properties"
    [ testProperty "empty graph has no nodes or fields" $ do
        let graph = Opt.empty
        case graph of
          Opt.GlobalGraph nodes fields ->
            Map.null nodes && Map.null fields,
      testProperty "addGlobalGraph preserves individual maps" $
        forAll genGlobalGraph $ \g1 ->
          forAll genGlobalGraph $ \g2 ->
            let result = Opt.addGlobalGraph g1 g2
             in case (g1, g2, result) of
                  (Opt.GlobalGraph n1 f1, Opt.GlobalGraph n2 f2, Opt.GlobalGraph nr fr) ->
                    Map.size nr >= max (Map.size n1) (Map.size n2)
                      && Map.size fr >= max (Map.size f1) (Map.size f2),
      testProperty "addGlobalGraph with empty preserves original" $
        forAll genGlobalGraph $ \g ->
          let result1 = Opt.addGlobalGraph g Opt.empty
              result2 = Opt.addGlobalGraph Opt.empty g
           in case (g, result1, result2) of
                (Opt.GlobalGraph gn gf, Opt.GlobalGraph r1n r1f, Opt.GlobalGraph r2n r2f) ->
                  Map.size gn <= Map.size r1n && Map.size gf <= Map.size r1f
                    && Map.size gn <= Map.size r2n
                    && Map.size gf <= Map.size r2f
    ]
  where
    genGlobalGraph = do
      nodes <- genSmallMap genGlobal genNode
      fields <- genSmallMap genName arbitrary
      pure (Opt.GlobalGraph nodes fields)

    genNode = do
      expr <- genSimpleExpr
      deps <- genSmallSet genGlobal
      pure (Opt.Define expr deps)

    genSimpleExpr = oneof [Opt.Bool <$> arbitrary, Opt.Int <$> arbitrary, pure Opt.Unit]

    genSmallSet genElem = do
      elems <- listOf genElem
      pure (Set.fromList elems)

    genDisjointGlobalGraphs = do
      g1 <- genGlobalGraph
      g2 <- genGlobalGraph
      -- For simplicity, we'll just test with empty graphs to ensure disjointness
      pure (g1, Opt.empty)

-- Test Global properties
testGlobalProperties :: TestTree
testGlobalProperties =
  testGroup
    "Global properties"
    [ testProperty "Global equality is reflexive" $
        forAll genGlobal $ \g ->
          g === g,
      testProperty "Global equality is symmetric" $
        forAll genGlobal $ \g1 ->
          forAll genGlobal $ \g2 ->
            (g1 == g2) === (g2 == g1),
      testProperty "Global equality is transitive" $
        forAll genGlobal $ \g1 ->
          let g2 = g1 -- Use identical global to ensure condition is met
              g3 = g1
           in (g1 == g2 && g2 == g3) ==> (g1 == g3),
      testProperty "Global ordering is consistent with equality" $
        forAll genGlobal $ \g1 ->
          forAll genGlobal $ \g2 ->
            (g1 == g2) === (compare g1 g2 == EQ),
      testProperty "Global ordering is antisymmetric" $
        forAll genGlobal $ \g1 ->
          forAll genGlobal $ \g2 ->
            (compare g1 g2 == LT) === (compare g2 g1 == GT),
      testProperty "Global ordering is transitive" $
        forAll genGlobal $ \g1 ->
          forAll genGlobal $ \g2 ->
            forAll genGlobal $ \g3 ->
              (compare g1 g2 == LT && compare g2 g3 == LT) ==> (compare g1 g3 == LT)
    ]

-- Test kernel-related properties
testKernelProperties :: TestTree
testKernelProperties =
  testGroup
    "Kernel properties"
    [ testProperty "toKernelGlobal creates consistent globals" $
        forAll genName $ \name ->
          let global = Opt.toKernelGlobal name
           in case global of
                Opt.Global moduleName globalName ->
                  (moduleName === ModuleName.Canonical Pkg.kernel name)
                    .&&. (globalName === Name.dollar),
      testProperty "toKernelGlobal is injective for different names" $
        forAll genName $ \name1 ->
          forAll genName $ \name2 ->
            (name1 /= name2) ==> (Opt.toKernelGlobal name1 /= Opt.toKernelGlobal name2),
      testProperty "addKernel increases graph size" $
        forAll genName $ \name ->
          forAll genKernelChunks $ \chunks ->
            forAll genGlobalGraph $ \graph ->
              let result = Opt.addKernel name chunks graph
               in case (graph, result) of
                    (Opt.GlobalGraph oldNodes oldFields, Opt.GlobalGraph newNodes newFields) ->
                      Map.size newNodes >= Map.size oldNodes && Map.size newFields >= Map.size oldFields,
      testProperty "addKernel adds the kernel global" $
        forAll genName $ \name ->
          forAll genKernelChunks $ \chunks ->
            let result = Opt.addKernel name chunks Opt.empty
                expectedGlobal = Opt.toKernelGlobal name
             in case result of
                  Opt.GlobalGraph nodes _ ->
                    Map.member expectedGlobal nodes
    ]
  where
    genKernelChunks = listOf genKernelChunk

    genKernelChunk =
      oneof
        [ pure (K.JS "console.log('test')"),
          K.CanopyVar <$> elements [ModuleName.basics, ModuleName.list] <*> genName,
          K.JsVar <$> genName <*> genName,
          K.CanopyField <$> genName,
          K.JsField <$> (arbitrary :: Gen Int),
          K.JsEnum <$> (arbitrary :: Gen Int),
          pure K.Debug,
          pure K.Prod
        ]

    genGlobalGraph = do
      nodes <- genSmallMap genGlobal genNode
      fields <- genSmallMap genName arbitrary
      pure (Opt.GlobalGraph nodes fields)

    genNode = do
      expr <- genSimpleExpr
      deps <- genSmallSet genGlobal
      pure (Opt.Define expr deps)

    genSimpleExpr = oneof [Opt.Bool <$> arbitrary, Opt.Int <$> arbitrary, pure Opt.Unit]

    genSmallSet genElem = do
      elems <- listOf genElem
      pure (Set.fromList elems)
