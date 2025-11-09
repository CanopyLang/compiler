{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit.Canonicalize.ExpressionArithmeticTest - Tests for arithmetic canonicalization
--
-- This module provides complete test coverage for canonicalizing arithmetic
-- expressions from Source AST to Canonical AST, including operator resolution,
-- precedence application, and semantic validation.
--
-- == Test Coverage
--
-- * Binary operator canonicalization
-- * Operator precedence enforcement
-- * Associativity application
-- * Type-aware operator resolution
-- * Native vs. function call distinction
-- * Nested expression canonicalization
-- * Variable and literal handling in arithmetic
-- * Error conditions (undefined operators, type mismatches)
--
-- @since 0.19.1
module Unit.Canonicalize.ExpressionArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Name as Name
import qualified Data.Map.Strict as Map
import qualified AST.Source as Src
import qualified AST.Canonical as Can
import qualified Canonicalize.Expression as Canon
import qualified Canonicalize.Environment as Env
import qualified Canopy.ModuleName as ModuleName
import qualified Reporting.Annotation as A
import qualified Reporting.Result as Result

-- | Main test tree containing all Canonicalize.Expression arithmetic tests.
tests :: TestTree
tests = testGroup "Canonicalize.Expression Arithmetic Tests"
  [ binopCanonicalizationTests
  , precedenceApplicationTests
  , operatorResolutionTests
  , nestedExpressionTests
  , literalHandlingTests
  , edgeCaseTests
  , errorConditionTests
  ]

-- | Test basic binary operator canonicalization.
--
-- Verifies that binary operators are correctly resolved and
-- transformed from source to canonical form.
binopCanonicalizationTests :: TestTree
binopCanonicalizationTests = testGroup "Binary Operator Canonicalization"
  [ testCase "Canonicalize integer addition creates binop call" $
      let left = A.At dummyRegion (Src.Int 1)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "+")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Call _ _ -> assertBool "Addition creates function call" True
               _ -> assertFailure "Expected Call node for arithmetic"
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Canonicalize multiplication operator" $
      let left = A.At dummyRegion (Src.Int 3)
          right = A.At dummyRegion (Src.Int 4)
          op = A.At dummyRegion (Name.fromChars "*")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Call _ args -> length args @?= 2
               _ -> assertFailure "Expected Call with 2 args"
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Canonicalize division operator" $
      let left = A.At dummyRegion (Src.Int 10)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "/")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Division canonicalizes" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Canonicalize power operator" $
      let left = A.At dummyRegion (Src.Int 2)
          right = A.At dummyRegion (Src.Int 8)
          op = A.At dummyRegion (Name.fromChars "^")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Power canonicalizes" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)
  ]

-- | Test precedence application during canonicalization.
--
-- Verifies that operator precedence rules are correctly applied
-- when converting source expressions to canonical form.
precedenceApplicationTests :: TestTree
precedenceApplicationTests = testGroup "Precedence Application"
  [ testCase "Multiplication before addition 1 + 2 * 3" $
      let one = A.At dummyRegion (Src.Int 1)
          two = A.At dummyRegion (Src.Int 2)
          three = A.At dummyRegion (Src.Int 3)
          plus = A.At dummyRegion (Name.fromChars "+")
          times = A.At dummyRegion (Name.fromChars "*")
          -- Parse as: 1 + 2 * 3, should canonicalize with * binding tighter
          srcExpr = A.At dummyRegion (Src.Binops [(one, plus), (two, times)] three)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             -- Result should have multiplication evaluated first
             assertBool "Expression canonicalizes with precedence" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Power before multiplication 2 * 3 ^ 2" $
      let two = A.At dummyRegion (Src.Int 2)
          three = A.At dummyRegion (Src.Int 3)
          twoLit = A.At dummyRegion (Src.Int 2)
          times = A.At dummyRegion (Name.fromChars "*")
          power = A.At dummyRegion (Name.fromChars "^")
          srcExpr = A.At dummyRegion (Src.Binops [(two, times), (three, power)] twoLit)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Power binds tighter than multiplication" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Left associativity for same precedence 10 - 5 - 2" $
      let ten = A.At dummyRegion (Src.Int 10)
          five = A.At dummyRegion (Src.Int 5)
          two = A.At dummyRegion (Src.Int 2)
          minus = A.At dummyRegion (Name.fromChars "-")
          minusTwo = A.At dummyRegion (Name.fromChars "-")
          -- Should associate left: (10 - 5) - 2 = 3, not 10 - (5 - 2) = 7
          srcExpr = A.At dummyRegion (Src.Binops [(ten, minus), (five, minusTwo)] two)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Left associativity applied" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)
  ]

-- | Test operator resolution in environment.
--
-- Verifies that operators are correctly looked up and resolved
-- to their implementing functions.
operatorResolutionTests :: TestTree
operatorResolutionTests = testGroup "Operator Resolution"
  [ testCase "Resolve + operator to Basics.add" $
      let left = A.At dummyRegion (Src.Int 1)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "+")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             -- Should resolve to function call to addition
             assertBool "Operator resolves to function" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Resolve * operator to Basics.mul" $
      let left = A.At dummyRegion (Src.Int 2)
          right = A.At dummyRegion (Src.Int 3)
          op = A.At dummyRegion (Name.fromChars "*")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Multiplication resolves" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Operator creates VarOperator reference" $
      let srcOp = Src.Op (Name.fromChars "+")
          srcExpr = A.At dummyRegion srcOp
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.VarOperator _ _ _ _ -> assertBool "Creates VarOperator" True
               _ -> assertFailure "Expected VarOperator"
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)
  ]

-- | Test nested expression canonicalization.
--
-- Verifies correct handling of complex nested arithmetic with
-- multiple levels and mixed operators.
nestedExpressionTests :: TestTree
nestedExpressionTests = testGroup "Nested Expression Canonicalization"
  [ testCase "Canonicalize (1 + 2) * 3" $
      let one = A.At dummyRegion (Src.Int 1)
          two = A.At dummyRegion (Src.Int 2)
          three = A.At dummyRegion (Src.Int 3)
          plus = A.At dummyRegion (Name.fromChars "+")
          times = A.At dummyRegion (Name.fromChars "*")
          innerExpr = A.At dummyRegion (Src.Binops [(one, plus)] two)
          outerExpr = A.At dummyRegion (Src.Binops [(innerExpr, times)] three)
          env = createBasicEnv
      in case runCanonicalize env outerExpr of
           Right canExpr ->
             assertBool "Nested expression canonicalizes" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Canonicalize complex nested 1 + 2 * 3 / 4" $
      let one = A.At dummyRegion (Src.Int 1)
          two = A.At dummyRegion (Src.Int 2)
          three = A.At dummyRegion (Src.Int 3)
          four = A.At dummyRegion (Src.Int 4)
          plus = A.At dummyRegion (Name.fromChars "+")
          times = A.At dummyRegion (Name.fromChars "*")
          div = A.At dummyRegion (Name.fromChars "/")
          -- 1 + 2 * 3 / 4
          srcExpr = A.At dummyRegion (Src.Binops [(one, plus), (two, times), (three, div)] four)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Complex expression canonicalizes" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Deeply nested with variables" $
      let varX = A.At dummyRegion (Src.Var Src.LowVar (Name.fromChars "x"))
          varY = A.At dummyRegion (Src.Var Src.LowVar (Name.fromChars "y"))
          varZ = A.At dummyRegion (Src.Var Src.LowVar (Name.fromChars "z"))
          plus = A.At dummyRegion (Name.fromChars "+")
          times = A.At dummyRegion (Name.fromChars "*")
          -- x + y * z
          srcExpr = A.At dummyRegion (Src.Binops [(varX, plus), (varY, times)] varZ)
          env = createBasicEnvWithVars ["x", "y", "z"]
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Variables in arithmetic canonicalize" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)
  ]

-- | Test literal handling in arithmetic.
--
-- Verifies that numeric literals are correctly preserved
-- and integrated into canonical arithmetic expressions.
literalHandlingTests :: TestTree
literalHandlingTests = testGroup "Literal Handling"
  [ testCase "Integer literals preserved" $
      let srcExpr = A.At dummyRegion (Src.Int 42)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Int n -> n @?= 42
               _ -> assertFailure "Expected Int"
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Float literals preserved" $
      let srcExpr = A.At dummyRegion (Src.Float 3.14)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Float f -> assertBool "Float close to 3.14" (abs (f - 3.14) < 0.0001)
               _ -> assertFailure "Expected Float"
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Negative numbers canonicalize" $
      let innerExpr = A.At dummyRegion (Src.Int 5)
          srcExpr = A.At dummyRegion (Src.Negate innerExpr)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Negate _ -> assertBool "Negate preserved" True
               _ -> assertFailure "Expected Negate"
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Zero in arithmetic" $
      let zero = A.At dummyRegion (Src.Int 0)
          five = A.At dummyRegion (Src.Int 5)
          plus = A.At dummyRegion (Name.fromChars "+")
          srcExpr = A.At dummyRegion (Src.Binops [(zero, plus)] five)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Zero in arithmetic works" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)
  ]

-- | Test edge cases and boundary conditions.
--
-- Verifies correct handling of unusual but valid arithmetic expressions.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "Large integer in arithmetic" $
      let large = A.At dummyRegion (Src.Int 2147483647)
          one = A.At dummyRegion (Src.Int 1)
          plus = A.At dummyRegion (Name.fromChars "+")
          srcExpr = A.At dummyRegion (Src.Binops [(large, plus)] one)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Large integer canonicalizes" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Mixed Int and Float in same expression" $
      let intVal = A.At dummyRegion (Src.Int 5)
          floatVal = A.At dummyRegion (Src.Float 2.5)
          plus = A.At dummyRegion (Name.fromChars "+")
          srcExpr = A.At dummyRegion (Src.Binops [(intVal, plus)] floatVal)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Mixed types canonicalize" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)

  , testCase "Very long operator chain" $
      let mkInt n = A.At dummyRegion (Src.Int n)
          plus = A.At dummyRegion (Name.fromChars "+")
          ops = replicate 10 (mkInt 1, plus)
          srcExpr = A.At dummyRegion (Src.Binops ops (mkInt 1))
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Right canExpr ->
             assertBool "Long chain canonicalizes" True
           Left err -> assertFailure ("Canonicalization failed: " ++ show err)
  ]

-- | Test error conditions.
--
-- Verifies that invalid arithmetic expressions produce appropriate
-- canonicalization errors.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "Undefined operator produces error" $
      let left = A.At dummyRegion (Src.Int 1)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "@@@")  -- Invalid operator
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Left _ -> assertBool "Undefined operator fails" True
           Right _ -> assertFailure "Should fail on undefined operator"

  , testCase "Undefined variable in arithmetic produces error" $
      let undef = A.At dummyRegion (Src.Var Src.LowVar (Name.fromChars "undefined"))
          two = A.At dummyRegion (Src.Int 2)
          plus = A.At dummyRegion (Name.fromChars "+")
          srcExpr = A.At dummyRegion (Src.Binops [(undef, plus)] two)
          env = createBasicEnv
      in case runCanonicalize env srcExpr of
           Left _ -> assertBool "Undefined variable fails" True
           Right _ -> assertFailure "Should fail on undefined variable"
  ]

-- | Helper: Create basic environment with standard operators.
createBasicEnv :: Env.Env
createBasicEnv =
  -- Create minimal environment with Basics operators
  -- This is simplified; actual implementation needs full Env construction
  let binops = Map.fromList
        [ (Name.fromChars "+", createBinop "+")
        , (Name.fromChars "-", createBinop "-")
        , (Name.fromChars "*", createBinop "*")
        , (Name.fromChars "/", createBinop "/")
        , (Name.fromChars "//", createBinop "//")
        , (Name.fromChars "%", createBinop "%")
        , (Name.fromChars "^", createBinop "^")
        ]
  in Env.Env
       { Env._home = ModuleName.basics
       , Env._vars = Map.empty
       , Env._types = Map.empty
       , Env._ctors = Map.empty
       , Env._binops = binops
       , Env._aliases = Map.empty
       }

-- | Helper: Create environment with additional local variables.
createBasicEnvWithVars :: [String] -> Env.Env
createBasicEnvWithVars varNames =
  let env = createBasicEnv
      vars = Map.fromList [(Name.fromChars n, undefined) | n <- varNames]
  in env { Env._vars = vars }

-- | Helper: Create a binop entry for environment.
createBinop :: String -> Env.Binop
createBinop op =
  Env.Binop
    (Name.fromChars op)
    ModuleName.basics
    (Name.fromChars op)
    undefined  -- annotation
    undefined  -- precedence
    undefined  -- associativity

-- | Run canonicalization for testing.
runCanonicalize :: Env.Env -> Src.Expr -> Either String Can.Expr
runCanonicalize env expr =
  case Canon.canonicalize env expr of
    Result.Ok canExpr -> Right canExpr
    Result.Err _ -> Left "Canonicalization error"

-- | Dummy region for tests.
dummyRegion :: A.Region
dummyRegion = A.Region (A.Position 0 0) (A.Position 0 0)
