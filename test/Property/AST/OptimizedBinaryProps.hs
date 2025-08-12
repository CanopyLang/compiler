module Property.AST.OptimizedBinaryProps (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import Data.Binary (decode, encode)
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map as Map
import qualified Data.Name as Name
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests =
  testGroup
    "AST.Optimized Binary Props"
    [ testExprBinaryRoundTrip
    ]

-- Generators (restricted to a safe, representative subset)

genName :: Gen Name.Name
genName = do
  first <- elements ['a' .. 'z']
  rest <- listOf (elements (['a' .. 'z'] ++ ['A' .. 'Z'] ++ ['0' .. '9']))
  pure (Name.fromChars (first : rest))

genSimpleExpr :: Int -> Gen Opt.Expr
genSimpleExpr 0 =
  oneof
    [ Opt.Bool <$> arbitrary,
      Opt.Int <$> arbitrary,
      Opt.Str . Name.toCanopyString <$> genName,
      pure Opt.Unit,
      Opt.Accessor <$> genName
    ]
genSimpleExpr n =
  oneof
    [ Opt.Bool <$> arbitrary,
      Opt.Int <$> arbitrary,
      Opt.Str . Name.toCanopyString <$> genName,
      Opt.VarLocal <$> genName,
      Opt.VarGlobal <$> genGlobal,
      Opt.List <$> smallList (genSimpleExpr (n -1)),
      Opt.Function <$> smallList genName <*> genSimpleExpr (n -1),
      Opt.Call <$> genSimpleExpr (n -1) <*> smallList (genSimpleExpr (n -1)),
      Opt.If <$> smallList ((,) <$> genSimpleExpr (n -1) <*> genSimpleExpr (n -1)) <*> genSimpleExpr (n -1),
      Opt.Let <$> genDef (n -1) <*> genSimpleExpr (n -1),
      Opt.Access <$> genSimpleExpr (n -1) <*> genName,
      Opt.Update <$> genSimpleExpr (n -1) <*> genMap genName (genSimpleExpr (n -1)),
      Opt.Record <$> genMap genName (genSimpleExpr (n -1)),
      pure Opt.Unit,
      Opt.Tuple <$> genSimpleExpr (n -1) <*> genSimpleExpr (n -1) <*> frequency [(3, pure Nothing), (1, Just <$> genSimpleExpr (n -1))]
    ]

genDef :: Int -> Gen Opt.Def
genDef n =
  oneof
    [ Opt.Def <$> genName <*> genSimpleExpr n,
      Opt.TailDef <$> genName <*> smallList genName <*> genSimpleExpr n
    ]

genGlobal :: Gen Opt.Global
genGlobal = do
  m <- elements [ModuleName.basics, ModuleName.list, ModuleName.jsonDecode]
  n <- genName
  pure (Opt.Global m n)

smallList :: Gen a -> Gen [a]
smallList g = choose (0, 3) >>= flip vectorOf g

genMap :: Ord k => Gen k -> Gen v -> Gen (Map.Map k v)
genMap k v = do
  keys <- smallList k
  vals <- vectorOf (length keys) v
  pure (Map.fromList (zip keys vals))

-- Properties

testExprBinaryRoundTrip :: TestTree
testExprBinaryRoundTrip =
  localOption (QuickCheckMaxSize 8) $
    testProperty "encode . decode . encode is stable for Expr" $
      forAll (resize 8 (sized genSimpleExpr)) $ \e ->
        let bs = encode e
            e' = decode bs :: Opt.Expr
         in encode e' === bs
