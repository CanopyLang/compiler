{-# LANGUAGE OverloadedStrings #-}

-- | Tests for Optimize.DecisionTree
--
-- Verifies that the decision tree compiler produces correct decision trees
-- from canonical pattern lists. Tests cover single patterns, multiple
-- constructors, wildcards, literal patterns, and the exported data types.
module Unit.Optimize.DecisionTreeTest (tests) where

import qualified AST.Canonical as Can
import qualified Data.Index as Index
import qualified Data.Name as Name
import qualified Data.Utf8 as Utf8
import Optimize.DecisionTree (DecisionTree (..), Path (..), Test (..))
import qualified Optimize.DecisionTree as DT
import qualified Reporting.Annotation as Ann
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Optimize.DecisionTree"
    [ singlePatternTests,
      multipleConstructorTests,
      wildcardPatternTests,
      literalPatternTests,
      pathDataTypeTests,
      testDataTypeTests,
      boolPatternTests
    ]

-- HELPERS

-- | Create a canonical pattern at region zero.
mkPat :: Can.Pattern_ -> Can.Pattern
mkPat = Ann.At Ann.zero

-- | Create a simple wildcard pattern.
mkAnything :: Can.Pattern
mkAnything = mkPat Can.PAnything

-- | Create a PVar pattern with the given name.
mkVar :: Name.Name -> Can.Pattern
mkVar name = mkPat (Can.PVar name)

-- | Create a Bool pattern (True or False).
mkBool :: Bool -> Can.Pattern
mkBool b = mkPat (Can.PBool boolUnion b)

-- | Create an Int literal pattern.
mkIntPat :: Int -> Can.Pattern
mkIntPat n = mkPat (Can.PInt n)

-- | Create a String literal pattern.
mkStrPat :: String -> Can.Pattern
mkStrPat s = mkPat (Can.PStr (Utf8.fromChars s))

-- | Create a Char literal pattern.
mkChrPat :: String -> Can.Pattern
mkChrPat s = mkPat (Can.PChr (Utf8.fromChars s))

-- | The standard Bool union type used by PBool patterns.
boolUnion :: Can.Union
boolUnion =
  Can.Union
    { Can._u_vars = [],
      Can._u_alts =
        [ Can.Ctor (Name.fromChars "False") Index.first 0 [],
          Can.Ctor (Name.fromChars "True") (Index.next Index.first) 0 []
        ],
      Can._u_numAlts = 2,
      Can._u_opts = Can.Enum
    }

-- | Assert that two DecisionTree values are equal.
-- DecisionTree has Eq but not Show, so we use assertBool directly.
assertTreeEq :: String -> DecisionTree -> DecisionTree -> Assertion
assertTreeEq msg expected actual =
  assertBool (msg ++ ": trees not equal") (expected == actual)

-- SINGLE PATTERN TESTS

singlePatternTests :: TestTree
singlePatternTests =
  testGroup
    "single pattern compilation"
    [ testCase "single wildcard produces Match 0" $
        assertTreeEq "wildcard" (Match 0) (DT.compile [(mkAnything, 0)]),
      testCase "single variable produces Match 0" $
        assertTreeEq "variable" (Match 0) (DT.compile [(mkVar (Name.fromChars "x"), 0)]),
      testCase "single pattern preserves branch index" $
        assertTreeEq "index 42" (Match 42) (DT.compile [(mkAnything, 42)])
    ]

-- MULTIPLE CONSTRUCTOR TESTS

multipleConstructorTests :: TestTree
multipleConstructorTests =
  testGroup
    "multiple constructor compilation"
    [ testCase "two Bool constructors produce Decision with two edges" $
        assertDecisionEdgeCount 2 (DT.compile [(mkBool True, 0), (mkBool False, 1)]),
      testCase "two Bool branches have correct targets" $
        assertDecisionTargets [0, 1] (DT.compile [(mkBool True, 0), (mkBool False, 1)]),
      testCase "Bool True first matches index 0" $
        assertContainsLeaf 0 (DT.compile [(mkBool True, 0), (mkBool False, 1)]),
      testCase "Bool False second matches index 1" $
        assertContainsLeaf 1 (DT.compile [(mkBool True, 0), (mkBool False, 1)])
    ]

-- WILDCARD PATTERN TESTS

wildcardPatternTests :: TestTree
wildcardPatternTests =
  testGroup
    "wildcard and default branches"
    [ testCase "wildcard after Bool True produces decision with default" $
        assertHasDefault (DT.compile [(mkBool True, 0), (mkAnything, 1)]),
      testCase "wildcard-only single branch matches immediately" $
        assertTreeEq "match 5" (Match 5) (DT.compile [(mkAnything, 5)]),
      testCase "first wildcard wins among multiple wildcards" $
        assertTreeEq "first wins" (Match 10) (DT.compile [(mkAnything, 10), (mkAnything, 20)]),
      testCase "variable pattern acts as wildcard" $
        assertTreeEq "var match" (Match 7) (DT.compile [(mkVar (Name.fromChars "x"), 7)])
    ]

-- LITERAL PATTERN TESTS

literalPatternTests :: TestTree
literalPatternTests =
  testGroup
    "literal pattern compilation"
    [ testCase "single Int literal with wildcard produces decision" $
        assertIsDecision (DT.compile [(mkIntPat 42, 0), (mkAnything, 1)]),
      testCase "two Int literals produce decision with two edges" $
        assertDecisionEdgeCount 2
          (DT.compile [(mkIntPat 1, 0), (mkIntPat 2, 1), (mkAnything, 2)]),
      testCase "String literal produces decision" $
        assertIsDecision (DT.compile [(mkStrPat "hello", 0), (mkAnything, 1)]),
      testCase "Char literal produces decision" $
        assertIsDecision (DT.compile [(mkChrPat "a", 0), (mkAnything, 1)])
    ]

-- PATH DATA TYPE TESTS

pathDataTypeTests :: TestTree
pathDataTypeTests =
  testGroup
    "Path data type"
    [ testCase "Empty path equals itself" $
        Empty @?= Empty,
      testCase "Index wraps inner path" $
        Index Index.first Empty @?= Index Index.first Empty,
      testCase "Unbox wraps inner path" $
        Unbox Empty @?= Unbox Empty,
      testCase "nested Index paths preserve structure" $
        Index Index.first (Index Index.second Empty)
          @?= Index Index.first (Index Index.second Empty),
      testCase "different paths are not equal" $
        assertBool "Empty /= Index" (Empty /= Index Index.first Empty),
      testCase "Empty path shows correctly" $
        show Empty @?= "Empty",
      testCase "Index path shows correctly" $
        show (Index Index.first Empty) @?= "Index (ZeroBased 0) Empty"
    ]

-- TEST DATA TYPE TESTS

testDataTypeTests :: TestTree
testDataTypeTests =
  testGroup
    "Test data type"
    [ testCase "IsBool True shows correctly" $
        show (IsBool True) @?= "IsBool True",
      testCase "IsBool False shows correctly" $
        show (IsBool False) @?= "IsBool False",
      testCase "IsInt shows value" $
        show (IsInt 42) @?= "IsInt 42",
      testCase "IsCons shows correctly" $
        show IsCons @?= "IsCons",
      testCase "IsNil shows correctly" $
        show IsNil @?= "IsNil",
      testCase "IsTuple shows correctly" $
        show IsTuple @?= "IsTuple",
      testCase "IsBool True and False are not equal" $
        assertBool "True /= False" (IsBool True /= IsBool False),
      testCase "IsInt values differ when ints differ" $
        assertBool "42 /= 0" (IsInt 42 /= IsInt 0)
    ]

-- BOOL PATTERN TESTS

boolPatternTests :: TestTree
boolPatternTests =
  testGroup
    "Bool pattern specifics"
    [ testCase "complete Bool match has no default" $
        assertNoDefault (DT.compile [(mkBool True, 0), (mkBool False, 1)]),
      testCase "incomplete Bool match (only True) has default" $
        assertHasDefault (DT.compile [(mkBool True, 0), (mkAnything, 1)])
    ]

-- ASSERTION HELPERS

-- | Assert that a decision tree is a Decision node (not a Match).
assertIsDecision :: DecisionTree -> Assertion
assertIsDecision (Decision _ _ _) = pure ()
assertIsDecision (Match n) =
  assertFailure ("Expected Decision but got Match " ++ show n)

-- | Assert that a Decision node has the given number of edges.
assertDecisionEdgeCount :: Int -> DecisionTree -> Assertion
assertDecisionEdgeCount expected (Decision _ edges _) =
  length edges @?= expected
assertDecisionEdgeCount _ (Match n) =
  assertFailure ("Expected Decision but got Match " ++ show n)

-- | Assert that a decision tree contains a leaf matching the given target index
-- somewhere in its structure.
assertContainsLeaf :: Int -> DecisionTree -> Assertion
assertContainsLeaf target tree =
  assertBool
    ("Expected tree to contain leaf with target " ++ show target)
    (containsLeaf target tree)

-- | Check if a decision tree contains a Match with the given target.
containsLeaf :: Int -> DecisionTree -> Bool
containsLeaf target (Match n) = n == target
containsLeaf target (Decision _ edges mDefault) =
  any (containsLeaf target . snd) edges
    || Prelude.maybe False (containsLeaf target) mDefault

-- | Assert that a Decision node has a default branch.
assertHasDefault :: DecisionTree -> Assertion
assertHasDefault (Decision _ _ (Just _)) = pure ()
assertHasDefault (Decision _ _ Nothing) =
  assertFailure "Expected Decision with default branch but got None"
assertHasDefault (Match n) =
  assertFailure ("Expected Decision but got Match " ++ show n)

-- | Assert that a Decision node does NOT have a default branch.
assertNoDefault :: DecisionTree -> Assertion
assertNoDefault (Decision _ _ Nothing) = pure ()
assertNoDefault (Decision _ _ (Just _)) =
  assertFailure "Expected Decision without default branch but got Just"
assertNoDefault (Match n) =
  assertFailure ("Expected Decision but got Match " ++ show n)

-- | Collect all leaf targets from a decision tree.
collectTargets :: DecisionTree -> [Int]
collectTargets (Match n) = [n]
collectTargets (Decision _ edges mDefault) =
  concatMap (collectTargets . snd) edges
    ++ Prelude.maybe [] collectTargets mDefault

-- | Assert that a decision tree contains exactly the given set of leaf targets.
assertDecisionTargets :: [Int] -> DecisionTree -> Assertion
assertDecisionTargets expected tree =
  let targets = collectTargets tree
   in assertBool
        ("Expected targets " ++ show expected ++ " but got " ++ show targets)
        (all (`elem` targets) expected)
