module Unit.Parse.TypeTest (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Data.Name as Name
import qualified Parse.Primitives as P
import qualified Parse.Type as Ty
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Syntax as E
import Test.Tasty
import Test.Tasty.HUnit

parseType :: String -> Either E.Type Src.Type
parseType s = fst <$> P.fromByteString Ty.expression E.TIndentStart (C8.pack s)

tests :: TestTree
tests =
  testGroup
    "Parse.Type"
    [ testBasics,
      testTuples,
      testRecords,
      testApp,
      testLambda,
      testExtensibleRecord,
      testNestedTypes
    ]

testBasics :: TestTree
testBasics =
  testGroup
    "basics"
    [ testCase "type variable" $ case parseType "a" of
        Right (A.At _ (Src.TVar a)) -> Name.toChars a @?= "a"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "type constructor" $ case parseType "List a" of
        Right (A.At _ (Src.TType _ _ [A.At _ (Src.TVar _)])) -> return ()
        _ -> assertFailure "expected type application"
    ]

testTuples :: TestTree
testTuples =
  testGroup
    "tuples"
    [ testCase "unit" $ case parseType "()" of
        Right (A.At _ Src.TUnit) -> return ()
        _ -> assertFailure "expected TUnit",
      testCase "pair" $ case parseType "(Int, String)" of
        Right (A.At _ (Src.TTuple _ _ [])) -> return ()
        _ -> assertFailure "expected TTuple"
    ]

testRecords :: TestTree
testRecords = testCase "records" $ case parseType "{ x : Int, y : a }" of
  Right (A.At _ (Src.TRecord [(A.At _ x, _), (A.At _ y, _)] Nothing)) -> do
    x @?= Name.fromChars "x"
    y @?= Name.fromChars "y"
  _ -> assertFailure "expected record type"

testApp :: TestTree
testApp = testCase "qualified app" $ case parseType "Result.Result a b" of
  Right (A.At _ (Src.TTypeQual _ _ _ [_, _])) -> return ()
  _ -> assertFailure "expected qualified TType"

testLambda :: TestTree
testLambda = testCase "function type" $ case parseType "a -> b -> a" of
  Right (A.At _ (Src.TLambda _ (A.At _ (Src.TLambda _ _)))) -> return ()
  _ -> assertFailure "expected TLambda chain"

testExtensibleRecord :: TestTree
testExtensibleRecord = testCase "extensible record type" $ case parseType "{ r | a : Int }" of
  Right (A.At _ (Src.TRecord [(A.At _ a, _)] (Just (A.At _ r)))) -> do
    a @?= Name.fromChars "a"
    r @?= Name.fromChars "r"
  other -> assertFailure ("expected extensible record, got: " <> show other)

testNestedTypes :: TestTree
testNestedTypes = testCase "nested complex types" $ case parseType "{ r | a : { s | b : List (Maybe Int) }, t : ( Int, String ) }" of
  Right (A.At _ (Src.TRecord fields (Just (A.At _ r)))) -> do
    r @?= Name.fromChars "r"
    let names = fmap (\(A.At _ n, _) -> Name.toChars n) fields
    assertBool "has a and t" (all (`elem` names) ["a", "t"])
  other -> assertFailure ("expected nested record, got: " <> show other)
