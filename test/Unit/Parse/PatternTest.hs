module Unit.Parse.PatternTest (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Data.Name as Name
import qualified Parse.Pattern as Pat
import qualified Parse.Primitives as P
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Syntax as E
import Test.Tasty
import Test.Tasty.HUnit

parsePat :: String -> Either E.Pattern Src.Pattern
parsePat s = fmap fst $ P.fromByteString Pat.expression (\r c -> E.PStart r c) (C8.pack s)

tests :: TestTree
tests =
  testGroup
    "Parse.Pattern"
    [ testBasics,
      testLists,
      testTuples,
      testConstructors,
      testConsAndAlias,
      testNegatives
    ]

testBasics :: TestTree
testBasics =
  testGroup
    "basics"
    [ testCase "wildcard" $ do
        case parsePat "_" of
          Right (A.At _ Src.PAnything) -> return ()
          _ -> assertFailure "expected wildcard",
      testCase "variable" $ do
        case parsePat "x" of
          Right (A.At _ (Src.PVar name)) -> Name.toChars name @?= "x"
          _ -> assertFailure "expected PVar",
      testCase "int" $ do
        case parsePat "42" of
          Right (A.At _ (Src.PInt 42)) -> return ()
          _ -> assertFailure "expected PInt",
      testCase "char" $ do
        case parsePat "'x'" of
          Right (A.At _ (Src.PChr _)) -> return ()
          _ -> assertFailure "expected PChr",
      testCase "string" $ do
        case parsePat "\"hi\"" of
          Right (A.At _ (Src.PStr _)) -> return ()
          _ -> assertFailure "expected PStr"
    ]

testNegatives :: TestTree
testNegatives = testCase "float not allowed in pattern" $ do
  case parsePat "3.14" of
    Left (E.PFloat _ _ _) -> return ()
    other -> assertFailure ("expected PFloat error, got: " ++ show other)

testConsAndAlias :: TestTree
testConsAndAlias =
  testGroup
    "cons and alias"
    [ testCase "cons (::) pattern" $ do
        case parsePat "x :: xs" of
          Right (A.At _ (Src.PCons (A.At _ (Src.PVar _)) (A.At _ (Src.PVar _)))) -> return ()
          _ -> assertFailure "expected cons pattern",
      testCase "alias (as) pattern" $ do
        case parsePat "Just n as j" of
          Right (A.At _ (Src.PAlias _ (A.At _ name))) -> Name.toChars name @?= "j"
          other -> assertFailure ("expected alias pattern, got: " ++ show other)
    ]

testLists :: TestTree
testLists = testCase "lists" $ do
  case parsePat "[x, y]" of
    Right (A.At _ (Src.PList [_, _])) -> return ()
    _ -> assertFailure "expected 2-element list pattern"

testTuples :: TestTree
testTuples =
  testGroup
    "tuples"
    [ testCase "unit" $ do
        case parsePat "()" of
          Right (A.At _ Src.PUnit) -> return ()
          _ -> assertFailure "expected PUnit",
      testCase "pair" $ do
        case parsePat "(a, b)" of
          Right (A.At _ (Src.PTuple _ _ [])) -> return ()
          _ -> assertFailure "expected 2-tuple pattern"
    ]

testConstructors :: TestTree
testConstructors =
  testGroup
    "constructors"
    [ testCase "unqualified" $ do
        case parsePat "Just x" of
          Right (A.At _ (Src.PCtor _ _ [A.At _ (Src.PVar _)])) -> return ()
          _ -> assertFailure "expected PCtor with arg",
      testCase "qualified" $ do
        case parsePat "Maybe.Just x" of
          Right (A.At _ (Src.PCtorQual _ _ _ [A.At _ (Src.PVar _)])) -> return ()
          _ -> assertFailure "expected qualified ctor"
    ]
