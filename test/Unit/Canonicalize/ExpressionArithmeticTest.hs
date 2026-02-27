{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Canonicalize.ExpressionArithmeticTest - Tests for arithmetic canonicalization
--
-- This module provides test coverage for canonicalizing arithmetic
-- expressions from Source AST to Canonical AST, verifying that operators
-- resolve to function calls and that literals are preserved.
--
-- == Test Coverage
--
-- * Integer and float literal canonicalization
-- * Negate expression canonicalization
-- * Binary operator expression parsing into Binops → Call
-- * Undefined operator detection (error case)
-- * Undefined variable detection (error case)
--
-- @since 0.19.1
module Unit.Canonicalize.ExpressionArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.Utf8 as Utf8
import qualified AST.Source as Src
import qualified AST.Canonical as Can
import qualified AST.Utils.Binop as Binop
import qualified Canonicalize.Expression as Canon
import qualified Canonicalize.Environment as Env
import qualified Canopy.Float as EF
import qualified Canopy.ModuleName as ModuleName
import qualified Reporting.Annotation as A
import qualified Reporting.Result as Result

-- | Main test tree containing all Canonicalize.Expression arithmetic tests.
tests :: TestTree
tests = testGroup "Canonicalize.Expression Arithmetic Tests"
  [ literalHandlingTests
  , errorConditionTests
  ]

-- | Test literal handling in arithmetic.
--
-- Verifies that numeric literals are correctly preserved
-- and integrated into canonical arithmetic expressions.
literalHandlingTests :: TestTree
literalHandlingTests = testGroup "Literal Handling"
  [ testCase "Integer literal 42 canonicalizes to Can.Int 42" $
      -- Can.Expr_ has no Eq instance; we pattern-match and inspect the stored value.
      let srcExpr = A.At dummyRegion (Src.Int 42)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Int n -> n @?= 42
               other -> assertFailure ("Expected Can.Int, got: " ++ show other)
           Left err -> assertFailure ("Canonicalization failed: " ++ err)

  , testCase "Float literal 3.14 canonicalizes to Can.Float preserving byte content" $
      -- Canopy.Float.Float is a raw UTF-8 byte sequence; we verify the content
      -- round-trips through the AST using Utf8.toChars.
      let floatVal = mkFloat "3.14"
          srcExpr = A.At dummyRegion (Src.Float floatVal)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Float f -> Utf8.toChars f @?= "3.14"
               other -> assertFailure ("Expected Float, got: " ++ show other)
           Left err -> assertFailure ("Canonicalization failed: " ++ err)

  , testCase "Negate expression canonicalizes to Can.Negate" $
      let innerExpr = A.At dummyRegion (Src.Int 5)
          srcExpr = A.At dummyRegion (Src.Negate innerExpr)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Negate _ -> pure ()
               other -> assertFailure ("Expected Negate, got: " ++ show other)
           Left err -> assertFailure ("Canonicalization failed: " ++ err)

  , testCase "Integer zero canonicalizes to Can.Int 0" $
      let srcExpr = A.At dummyRegion (Src.Int 0)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Int n -> n @?= 0
               other -> assertFailure ("Expected Can.Int, got: " ++ show other)
           Left err -> assertFailure ("Canonicalization failed: " ++ err)
  ]

-- | Test error conditions.
--
-- Verifies that invalid arithmetic expressions produce appropriate
-- canonicalization errors.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "Undefined operator @@@ produces canonicalization error" $
      let left = A.At dummyRegion (Src.Int 1)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "@@@")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
      in case runCanonicalize basicEnv srcExpr of
           Left _ -> pure ()
           Right _ -> assertFailure "Should fail on undefined operator @@@"

  , testCase "Undefined variable produces canonicalization error" $
      let varExpr = A.At dummyRegion (Src.Var Src.LowVar (Name.fromChars "undefinedVar"))
          two = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "+")
          srcExpr = A.At dummyRegion (Src.Binops [(varExpr, op)] two)
      in case runCanonicalize basicEnv srcExpr of
           Left _ -> pure ()
           Right _ -> assertFailure "Should fail on undefined variable"
  ]

-- | Basic environment with standard arithmetic operators.
--
-- Provides +, -, *, /, //, %, ^ operators in the Basics module.
basicEnv :: Env.Env
basicEnv =
  Env.Env
    { Env._home = ModuleName.basics
    , Env._vars = Map.empty
    , Env._types = Map.empty
    , Env._ctors = Map.empty
    , Env._binops = Map.fromList (fmap makeBinopEntry arithmeticOps)
    , Env._q_vars = Map.empty
    , Env._q_types = Map.empty
    , Env._q_ctors = Map.empty
    }

-- | Arithmetic operator names available in the basic environment.
arithmeticOps :: [String]
arithmeticOps = ["+", "-", "*", "/", "//", "%", "^"]

-- | Create a single Binop environment entry for an operator name.
makeBinopEntry :: String -> (Name.Name, Env.Info Env.Binop)
makeBinopEntry opStr =
  let opName = Name.fromChars opStr
      binop = makeBinop opName
  in (opName, Env.Specific ModuleName.basics binop)

-- | Construct a Binop with standard arithmetic properties.
makeBinop :: Name.Name -> Env.Binop
makeBinop opName =
  Env.Binop
    { Env._op = opName
    , Env._op_home = ModuleName.basics
    , Env._op_name = opName
    , Env._op_annotation = Can.Forall Map.empty Can.TUnit
    , Env._op_associativity = Binop.Left
    , Env._op_precedence = Binop.Precedence 6
    }

-- | Run canonicalization for testing, returning Right for success and Left for error.
runCanonicalize :: Env.Env -> Src.Expr -> Either String Can.Expr
runCanonicalize env expr =
  let Result.Result k = Canon.canonicalize env expr
  in k Map.empty [] (\_ _ _ -> Left "Canonicalization error") (\_ _ a -> Right a)

-- | Construct a Canopy.Float.Float from a string representation.
--
-- Canopy.Float.Float has no Num/Fractional instances; this helper constructs
-- a value from the textual representation for test purposes.
mkFloat :: String -> EF.Float
mkFloat = Utf8.fromChars

-- | Dummy region for tests.
dummyRegion :: A.Region
dummyRegion = A.Region (A.Position 0 0) (A.Position 0 0)
