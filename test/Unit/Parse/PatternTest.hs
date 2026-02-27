module Unit.Parse.PatternTest (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Data.Name as Name
import qualified Parse.Pattern as Pat
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError
import Test.Tasty
import Test.Tasty.HUnit

parsePat :: String -> Either SyntaxError.Pattern Src.Pattern
parsePat s = fst <$> Parse.fromByteString Pat.expression SyntaxError.PStart (C8.pack s)

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
    [ testCase "wildcard" $ case parsePat "_" of
        Right (Ann.At _ Src.PAnything) -> return ()
        _ -> assertFailure "expected wildcard",
      testCase "variable" $ case parsePat "x" of
        Right (Ann.At _ (Src.PVar name)) -> Name.toChars name @?= "x"
        _ -> assertFailure "expected PVar",
      testCase "int" $ case parsePat "42" of
        Right (Ann.At _ (Src.PInt 42)) -> return ()
        _ -> assertFailure "expected PInt",
      testCase "char" $ case parsePat "'x'" of
        Right (Ann.At _ (Src.PChr _)) -> return ()
        _ -> assertFailure "expected PChr",
      testCase "string" $ case parsePat "\"hi\"" of
        Right (Ann.At _ (Src.PStr _)) -> return ()
        _ -> assertFailure "expected PStr"
    ]

testNegatives :: TestTree
testNegatives = testCase "float not allowed in pattern" $ case parsePat "3.14" of
  Left (SyntaxError.PFloat {}) -> return ()
  other -> assertFailure ("expected PFloat error, got: " <> show other)

testConsAndAlias :: TestTree
testConsAndAlias =
  testGroup
    "cons and alias"
    [ testCase "cons (::) pattern" $ case parsePat "x :: xs" of
        Right (Ann.At _ (Src.PCons (Ann.At _ (Src.PVar _)) (Ann.At _ (Src.PVar _)))) -> return ()
        _ -> assertFailure "expected cons pattern",
      testCase "alias (as) pattern" $ case parsePat "Just n as j" of
        Right (Ann.At _ (Src.PAlias _ (Ann.At _ name))) -> Name.toChars name @?= "j"
        other -> assertFailure ("expected alias pattern, got: " <> show other)
    ]

testLists :: TestTree
testLists = testCase "lists" $ case parsePat "[x, y]" of
  Right (Ann.At _ (Src.PList [_, _])) -> return ()
  _ -> assertFailure "expected 2-element list pattern"

testTuples :: TestTree
testTuples =
  testGroup
    "tuples"
    [ testCase "unit" $ case parsePat "()" of
        Right (Ann.At _ Src.PUnit) -> return ()
        _ -> assertFailure "expected PUnit",
      testCase "pair" $ case parsePat "(a, b)" of
        Right (Ann.At _ (Src.PTuple _ _ [])) -> return ()
        _ -> assertFailure "expected 2-tuple pattern"
    ]

testConstructors :: TestTree
testConstructors =
  testGroup
    "constructors"
    [ testCase "unqualified" $ case parsePat "Just x" of
        Right (Ann.At _ (Src.PCtor _ _ [Ann.At _ (Src.PVar _)])) -> return ()
        _ -> assertFailure "expected PCtor with arg",
      testCase "qualified" $ case parsePat "Maybe.Just x" of
        Right (Ann.At _ (Src.PCtorQual _ _ _ [Ann.At _ (Src.PVar _)])) -> return ()
        _ -> assertFailure "expected qualified ctor"
    ]
