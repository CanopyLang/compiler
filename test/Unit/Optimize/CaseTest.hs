{-# LANGUAGE OverloadedStrings #-}

-- | Tests for Optimize.Case
--
-- Verifies that case optimization produces correct Decider structures from
-- canonical pattern-expression pairs. Tests cover simple matches, two-branch
-- optimization, default branch handling, and the structure of emitted
-- Opt.Case nodes.
module Unit.Optimize.CaseTest (tests) where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Optimize.Case as Case
import qualified Reporting.Annotation as Ann
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Optimize.Case"
    [ singleBranchTests,
      twoBranchTests,
      defaultBranchTests,
      caseStructureTests,
      literalPatternTests
    ]

-- HELPERS

-- | Create a canonical pattern at region zero.
mkPat :: Can.Pattern_ -> Can.Pattern
mkPat = Ann.At Ann.zero

-- | Create a wildcard pattern.
mkAnything :: Can.Pattern
mkAnything = mkPat Can.PAnything

-- | Create a variable pattern.
mkVar :: Name.Name -> Can.Pattern
mkVar name = mkPat (Can.PVar name)

-- | Create a Bool pattern.
mkBool :: Bool -> Can.Pattern
mkBool b = mkPat (Can.PBool boolUnion b)

-- | Create an Int literal pattern.
mkIntPat :: Int -> Can.Pattern
mkIntPat n = mkPat (Can.PInt n)

-- | The standard Bool union type.
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

-- | Temporary name used for case compilation.
tempName :: Name.Name
tempName = Name.fromChars "$temp"

-- | Root name used for case compilation.
rootName :: Name.Name
rootName = Name.fromChars "$root"

-- | Build an optimized Case expression from pattern-expression pairs.
buildCase :: [(Can.Pattern, Opt.Expr)] -> Opt.Expr
buildCase = Case.optimize tempName rootName

-- | Check if an expression is an Opt.Case.
isCaseExpr :: Opt.Expr -> Bool
isCaseExpr (Opt.Case _ _ _ _) = True
isCaseExpr _ = False

-- | Assert that the result is an Opt.Case.
assertIsCaseExpr :: Opt.Expr -> Assertion
assertIsCaseExpr expr =
  assertBool
    ("Expected Opt.Case but got: " ++ take 80 (show expr))
    (isCaseExpr expr)

-- | Extract the decider from an Opt.Case expression, failing if not a Case.
extractDecider :: Opt.Expr -> IO (Opt.Decider Opt.Choice)
extractDecider (Opt.Case _ _ decider _) = pure decider
extractDecider other =
  assertFailure ("Expected Opt.Case but got: " ++ take 80 (show other))
    >> pure (Opt.Leaf (Opt.Inline Opt.Unit))

-- | Extract the jump table from an Opt.Case expression.
extractJumps :: Opt.Expr -> IO [(Int, Opt.Expr)]
extractJumps (Opt.Case _ _ _ jumps) = pure jumps
extractJumps other =
  assertFailure ("Expected Opt.Case but got: " ++ take 80 (show other))
    >> pure []

-- | Assert that a Decider is a Leaf node.
assertIsLeaf :: Opt.Decider Opt.Choice -> Assertion
assertIsLeaf (Opt.Leaf _) = pure ()
assertIsLeaf other =
  assertFailure ("Expected Leaf but got: " ++ take 80 (show other))

-- | Assert that a Decider is a Chain node.
assertIsChain :: Opt.Decider Opt.Choice -> Assertion
assertIsChain (Opt.Chain _ _ _) = pure ()
assertIsChain other =
  assertFailure ("Expected Chain but got: " ++ take 80 (show other))

-- SINGLE BRANCH TESTS

singleBranchTests :: TestTree
singleBranchTests =
  testGroup
    "single branch optimization"
    [ testCase "single wildcard produces Case with Leaf decider" $ do
        let result = buildCase [(mkAnything, Opt.Unit)]
        assertIsCaseExpr result
        decider <- extractDecider result
        assertIsLeaf decider,
      testCase "single variable produces Case with Leaf decider" $ do
        let result = buildCase [(mkVar (Name.fromChars "x"), Opt.Int 1)]
        assertIsCaseExpr result
        decider <- extractDecider result
        assertIsLeaf decider,
      testCase "single wildcard has empty jump table" $ do
        let result = buildCase [(mkAnything, Opt.Unit)]
        jumps <- extractJumps result
        length jumps @?= 0
    ]

-- TWO BRANCH TESTS

twoBranchTests :: TestTree
twoBranchTests =
  testGroup
    "two branch optimization"
    [ testCase "Bool True/False produces Chain decider" $ do
        let result = buildCase [(mkBool True, Opt.Bool True), (mkBool False, Opt.Bool False)]
        assertIsCaseExpr result
        decider <- extractDecider result
        assertIsChain decider,
      testCase "Bool branches produce correct structure" $ do
        let result = buildCase [(mkBool True, Opt.Int 1), (mkBool False, Opt.Int 0)]
        assertIsCaseExpr result,
      testCase "two Int literals with wildcard produce Case" $ do
        let result =
              buildCase
                [ (mkIntPat 1, Opt.Int 10),
                  (mkIntPat 2, Opt.Int 20),
                  (mkAnything, Opt.Int 0)
                ]
        assertIsCaseExpr result
    ]

-- DEFAULT BRANCH TESTS

defaultBranchTests :: TestTree
defaultBranchTests =
  testGroup
    "default branch handling"
    [ testCase "wildcard after specific pattern creates case" $ do
        let result = buildCase [(mkBool True, Opt.Int 1), (mkAnything, Opt.Int 0)]
        assertIsCaseExpr result,
      testCase "multiple wildcards collapse to first" $ do
        let result = buildCase [(mkAnything, Opt.Int 1), (mkAnything, Opt.Int 2)]
        assertIsCaseExpr result
        decider <- extractDecider result
        assertIsLeaf decider
    ]

-- CASE STRUCTURE TESTS

caseStructureTests :: TestTree
caseStructureTests =
  testGroup
    "Opt.Case structure"
    [ testCase "Case preserves temp name" $ do
        let result = buildCase [(mkAnything, Opt.Unit)]
        assertCaseTempName tempName result,
      testCase "Case preserves root name" $ do
        let result = buildCase [(mkAnything, Opt.Unit)]
        assertCaseRootName rootName result,
      testCase "single branch inlines expression (no jumps)" $ do
        let result = buildCase [(mkAnything, Opt.Int 99)]
        jumps <- extractJumps result
        length jumps @?= 0,
      testCase "Leaf decider contains Inline choice for single branch" $ do
        let result = buildCase [(mkAnything, Opt.Int 42)]
        decider <- extractDecider result
        assertLeafIsInline decider
    ]

-- LITERAL PATTERN TESTS

literalPatternTests :: TestTree
literalPatternTests =
  testGroup
    "literal pattern case optimization"
    [ testCase "Int pattern with default produces decision" $ do
        let result = buildCase [(mkIntPat 0, Opt.Int 100), (mkAnything, Opt.Int 200)]
        assertIsCaseExpr result
        decider <- extractDecider result
        assertIsChain decider,
      testCase "multiple Int patterns produce proper case" $ do
        let result =
              buildCase
                [ (mkIntPat 1, Opt.Int 10),
                  (mkIntPat 2, Opt.Int 20),
                  (mkIntPat 3, Opt.Int 30),
                  (mkAnything, Opt.Int 0)
                ]
        assertIsCaseExpr result
    ]

-- ASSERTION HELPERS

-- | Assert the temp name of a Case expression matches.
assertCaseTempName :: Name.Name -> Opt.Expr -> Assertion
assertCaseTempName expected (Opt.Case t _ _ _) =
  assertEqual "temp name" (Name.toChars expected) (Name.toChars t)
assertCaseTempName _ other =
  assertFailure ("Expected Opt.Case but got: " ++ take 80 (show other))

-- | Assert the root name of a Case expression matches.
assertCaseRootName :: Name.Name -> Opt.Expr -> Assertion
assertCaseRootName expected (Opt.Case _ r _ _) =
  assertEqual "root name" (Name.toChars expected) (Name.toChars r)
assertCaseRootName _ other =
  assertFailure ("Expected Opt.Case but got: " ++ take 80 (show other))

-- | Assert that a Leaf decider contains an Inline choice.
assertLeafIsInline :: Opt.Decider Opt.Choice -> Assertion
assertLeafIsInline (Opt.Leaf (Opt.Inline _)) = pure ()
assertLeafIsInline (Opt.Leaf (Opt.Jump n)) =
  assertFailure ("Expected Inline but got Jump " ++ show n)
assertLeafIsInline other =
  assertFailure ("Expected Leaf(Inline) but got: " ++ take 80 (show other))
