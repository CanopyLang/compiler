{-# OPTIONS_GHC -Wall #-}

module Unit.Optimize.ConstantFoldTest (tests) where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Data.Name as Name
import qualified Optimize.ConstantFold as ConstantFold
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Optimize.ConstantFold"
    [ integerFoldingTests,
      identityTests,
      absorptionTests,
      divisionByZeroTests,
      nestedFoldingTests,
      passThroughTests
    ]

-- | Assert that two Opt.Expr values are structurally equal via Show.
-- Opt.Expr lacks an Eq instance, so we compare string representations.
assertExprEq :: String -> Opt.Expr -> Opt.Expr -> Assertion
assertExprEq msg expected actual =
  assertEqual msg (show expected) (show actual)

-- INTEGER FOLDING

integerFoldingTests :: TestTree
integerFoldingTests =
  testGroup
    "integer constant folding"
    [ testCase "1 + 2 = 3" $
        assertExprEq "fold add" (Opt.Int 3)
          (ConstantFold.foldArith Can.Add (Opt.Int 1) (Opt.Int 2)),
      testCase "10 - 4 = 6" $
        assertExprEq "fold sub" (Opt.Int 6)
          (ConstantFold.foldArith Can.Sub (Opt.Int 10) (Opt.Int 4)),
      testCase "3 * 7 = 21" $
        assertExprEq "fold mul" (Opt.Int 21)
          (ConstantFold.foldArith Can.Mul (Opt.Int 3) (Opt.Int 7)),
      testCase "10 / 3 = 3 (integer division)" $
        assertExprEq "fold div" (Opt.Int 3)
          (ConstantFold.foldArith Can.Div (Opt.Int 10) (Opt.Int 3)),
      testCase "0 + 0 = 0" $
        assertExprEq "fold add zero" (Opt.Int 0)
          (ConstantFold.foldArith Can.Add (Opt.Int 0) (Opt.Int 0)),
      testCase "-5 + 3 = -2" $
        assertExprEq "fold add neg" (Opt.Int (-2))
          (ConstantFold.foldArith Can.Add (Opt.Int (-5)) (Opt.Int 3)),
      testCase "0 - 5 = -5" $
        assertExprEq "fold sub zero" (Opt.Int (-5))
          (ConstantFold.foldArith Can.Sub (Opt.Int 0) (Opt.Int 5))
    ]

-- IDENTITY RULES

identityTests :: TestTree
identityTests =
  testGroup
    "identity elimination"
    [ testCase "x + 0 = x" $
        assertExprEq "add identity right" varX
          (ConstantFold.foldArith Can.Add varX (Opt.Int 0)),
      testCase "0 + x = x" $
        assertExprEq "add identity left" varX
          (ConstantFold.foldArith Can.Add (Opt.Int 0) varX),
      testCase "x - 0 = x" $
        assertExprEq "sub identity" varX
          (ConstantFold.foldArith Can.Sub varX (Opt.Int 0)),
      testCase "x * 1 = x" $
        assertExprEq "mul identity right" varX
          (ConstantFold.foldArith Can.Mul varX (Opt.Int 1)),
      testCase "1 * x = x" $
        assertExprEq "mul identity left" varX
          (ConstantFold.foldArith Can.Mul (Opt.Int 1) varX)
    ]

-- ABSORPTION RULES

absorptionTests :: TestTree
absorptionTests =
  testGroup
    "absorption rules"
    [ testCase "x * 0 = 0" $
        assertExprEq "mul absorb right" (Opt.Int 0)
          (ConstantFold.foldArith Can.Mul varX (Opt.Int 0)),
      testCase "0 * x = 0" $
        assertExprEq "mul absorb left" (Opt.Int 0)
          (ConstantFold.foldArith Can.Mul (Opt.Int 0) varX)
    ]

-- DIVISION BY ZERO

divisionByZeroTests :: TestTree
divisionByZeroTests =
  testGroup
    "division by zero preservation"
    [ testCase "5 / 0 is NOT folded" $
        assertBool "should produce ArithBinop" $
          isArithBinop (ConstantFold.foldArith Can.Div (Opt.Int 5) (Opt.Int 0)),
      testCase "0 / 0 is NOT folded" $
        assertBool "should produce ArithBinop" $
          isArithBinop (ConstantFold.foldArith Can.Div (Opt.Int 0) (Opt.Int 0))
    ]

-- NESTED FOLDING

nestedFoldingTests :: TestTree
nestedFoldingTests =
  testGroup
    "nested folding"
    [ testCase "(1 + 2) * 3 = 9 via two folds" $
        let inner = ConstantFold.foldArith Can.Add (Opt.Int 1) (Opt.Int 2)
            result = ConstantFold.foldArith Can.Mul inner (Opt.Int 3)
         in assertExprEq "nested fold" (Opt.Int 9) result,
      testCase "(10 - 4) + (3 * 2) = 12 via three folds" $
        let left = ConstantFold.foldArith Can.Sub (Opt.Int 10) (Opt.Int 4)
            right = ConstantFold.foldArith Can.Mul (Opt.Int 3) (Opt.Int 2)
            result = ConstantFold.foldArith Can.Add left right
         in assertExprEq "nested fold 2" (Opt.Int 12) result
    ]

-- PASS-THROUGH

passThroughTests :: TestTree
passThroughTests =
  testGroup
    "non-constant expressions pass through"
    [ testCase "x + y produces ArithBinop" $
        assertBool "should produce ArithBinop" $
          isArithBinop (ConstantFold.foldArith Can.Add varX varY),
      testCase "x * y produces ArithBinop" $
        assertBool "should produce ArithBinop" $
          isArithBinop (ConstantFold.foldArith Can.Mul varX varY),
      testCase "x - y produces ArithBinop" $
        assertBool "should produce ArithBinop" $
          isArithBinop (ConstantFold.foldArith Can.Sub varX varY)
    ]

-- HELPERS

varX :: Opt.Expr
varX = Opt.VarLocal (Name.fromChars "x")

varY :: Opt.Expr
varY = Opt.VarLocal (Name.fromChars "y")

isArithBinop :: Opt.Expr -> Bool
isArithBinop (Opt.ArithBinop _ _ _) = True
isArithBinop _ = False
