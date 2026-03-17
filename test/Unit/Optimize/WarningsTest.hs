{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the post-optimization warning detection module.
--
-- Verifies that the optimizer correctly detects:
--
-- * Integer overflow beyond JavaScript's MAX_SAFE_INTEGER
-- * Division by constant zero
-- * Unreachable branches from constant boolean conditions
-- * No false positives for normal code
--
-- @since 0.20.1
module Unit.Optimize.WarningsTest (tests) where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Optimize.Warnings as OptWarn
import qualified Reporting.Warning as Warning
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Optimize.Warnings Tests"
    [ postFoldTests,
      preSimplifyTests
    ]

-- HELPERS

-- | Check if a warning is IntegerOverflow with expected value.
isOverflowWith :: Int -> Warning.Warning -> Bool
isOverflowWith expected (Warning.IntegerOverflow _ n) = n == expected
isOverflowWith _ _ = False

-- | Check if a warning is DivisionByZero.
isDivByZero :: Warning.Warning -> Bool
isDivByZero (Warning.DivisionByZero _) = True
isDivByZero _ = False

-- | Check if a warning is UnreachableBranch.
isUnreachable :: Warning.Warning -> Bool
isUnreachable (Warning.UnreachableBranch {}) = True
isUnreachable _ = False

-- POST-FOLD WARNING TESTS

postFoldTests :: TestTree
postFoldTests =
  testGroup
    "collectPostFoldWarnings"
    [ testCase "detects integer overflow above MAX_SAFE_INTEGER" $
        let expr = Opt.Int 9007199254740992
            warnings = OptWarn.collectPostFoldWarnings expr
         in assertBool "expected exactly one IntegerOverflow warning"
              (length warnings == 1 && all (isOverflowWith 9007199254740992) warnings),
      testCase "detects negative integer overflow below -MAX_SAFE_INTEGER" $
        let expr = Opt.Int (-9007199254740992)
            warnings = OptWarn.collectPostFoldWarnings expr
         in assertBool "expected exactly one IntegerOverflow warning"
              (length warnings == 1 && all (isOverflowWith (-9007199254740992)) warnings),
      testCase "no overflow for MAX_SAFE_INTEGER itself" $
        let expr = Opt.Int 9007199254740991
            warnings = OptWarn.collectPostFoldWarnings expr
         in assertBool "expected no warnings" (null warnings),
      testCase "detects division by constant zero" $
        let expr = Opt.ArithBinop Can.Div (Opt.Int 1) (Opt.Int 0)
            warnings = OptWarn.collectPostFoldWarnings expr
         in assertBool "expected exactly one DivisionByZero warning"
              (length warnings == 1 && all isDivByZero warnings),
      testCase "no warning for division by nonzero" $
        let expr = Opt.ArithBinop Can.Div (Opt.Int 10) (Opt.Int 2)
            warnings = OptWarn.collectPostFoldWarnings expr
         in assertBool "expected no warnings" (null warnings),
      testCase "no warning for simple integer literal" $
        let expr = Opt.Int 42
            warnings = OptWarn.collectPostFoldWarnings expr
         in assertBool "expected no warnings" (null warnings),
      testCase "no warning for boolean literal" $
        let expr = Opt.Bool True
            warnings = OptWarn.collectPostFoldWarnings expr
         in assertBool "expected no warnings" (null warnings),
      testCase "no warning for addition of safe integers" $
        let expr = Opt.ArithBinop Can.Add (Opt.Int 1) (Opt.Int 2)
            warnings = OptWarn.collectPostFoldWarnings expr
         in assertBool "expected no warnings" (null warnings)
    ]

-- PRE-SIMPLIFY WARNING TESTS

preSimplifyTests :: TestTree
preSimplifyTests =
  testGroup
    "collectPreSimplifyWarnings"
    [ testCase "detects if True dead else branch" $
        let expr = Opt.If [(Opt.Bool True, Opt.Int 1)] (Opt.Int 2)
            warnings = OptWarn.collectPreSimplifyWarnings expr
         in assertBool "expected exactly one UnreachableBranch warning"
              (length warnings == 1 && all isUnreachable warnings),
      testCase "detects if False dead then branch" $
        let expr = Opt.If [(Opt.Bool False, Opt.Int 1)] (Opt.Int 2)
            warnings = OptWarn.collectPreSimplifyWarnings expr
         in assertBool "expected exactly one UnreachableBranch warning"
              (length warnings == 1 && all isUnreachable warnings),
      testCase "no warning for non-constant condition" $
        let expr = Opt.If [(Opt.Int 1, Opt.Int 2)] (Opt.Int 3)
            warnings = OptWarn.collectPreSimplifyWarnings expr
         in assertBool "expected no warnings" (null warnings),
      testCase "no warning for simple expression" $
        let expr = Opt.Int 42
            warnings = OptWarn.collectPreSimplifyWarnings expr
         in assertBool "expected no warnings" (null warnings)
    ]
