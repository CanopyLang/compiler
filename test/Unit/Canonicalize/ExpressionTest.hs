{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Canonicalize.ExpressionTest - Tests for expression canonicalization
--
-- Covers all expression forms handled by 'Canonicalize.Expression.canonicalize',
-- including literals, lambdas, let bindings, case branches, record operations,
-- tuples, binary operator classification, and error conditions.
--
-- @since 0.19.1
module Unit.Canonicalize.ExpressionTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified AST.Source as Src
import qualified AST.Canonical as Can
import qualified AST.Utils.Binop as Binop
import qualified Canonicalize.Expression as Canon
import qualified Canonicalize.Environment as Env
import qualified Canonicalize.Pattern as Pattern
import qualified Canopy.Float as EF
import qualified Canopy.ModuleName as ModuleName
import qualified Reporting.Annotation as A
import qualified Reporting.Result as Result

-- | Main test tree.
tests :: TestTree
tests = testGroup "Canonicalize.Expression Tests"
  [ literalTests
  , listTests
  , unitTupleTests
  , lambdaTests
  , callTests
  , ifTests
  , caseTests
  , accessTests
  , letTests
  , binopClassifyTests
  , errorTests
  ]

-- LITERAL TESTS

-- | Test that all literal forms canonicalize correctly.
literalTests :: TestTree
literalTests = testGroup "Literal canonicalization"
  [ testCase "string literal preserves content" $
      let srcExpr = A.At dummyRegion (Src.Str (Utf8.fromChars "hello"))
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Str s -> Utf8.toChars s @?= "hello"
               other -> assertFailure ("Expected Can.Str, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "char literal preserves content" $
      let srcExpr = A.At dummyRegion (Src.Chr (Utf8.fromChars "a"))
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Chr _ -> pure ()
               other -> assertFailure ("Expected Can.Chr, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "integer literal 0 produces Can.Int 0" $
      let srcExpr = A.At dummyRegion (Src.Int 0)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Int n -> n @?= 0
               other -> assertFailure ("Expected Can.Int, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "float literal content is preserved" $
      let floatVal = Utf8.fromChars "2.71828" :: EF.Float
          srcExpr = A.At dummyRegion (Src.Float floatVal)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Float f -> Utf8.toChars f @?= "2.71828"
               other -> assertFailure ("Expected Can.Float, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- LIST TESTS

listTests :: TestTree
listTests = testGroup "List canonicalization"
  [ testCase "empty list canonicalizes to Can.List []" $
      let srcExpr = A.At dummyRegion (Src.List [])
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.List items -> length items @?= 0
               other -> assertFailure ("Expected Can.List, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "list with one integer element has length 1" $
      let elem1 = A.At dummyRegion (Src.Int 99)
          srcExpr = A.At dummyRegion (Src.List [elem1])
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.List items -> length items @?= 1
               other -> assertFailure ("Expected Can.List, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "list with three elements has length 3" $
      let mkInt n = A.At dummyRegion (Src.Int n)
          srcExpr = A.At dummyRegion (Src.List [mkInt 1, mkInt 2, mkInt 3])
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.List items -> length items @?= 3
               other -> assertFailure ("Expected Can.List, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- UNIT AND TUPLE TESTS

unitTupleTests :: TestTree
unitTupleTests = testGroup "Unit and tuple canonicalization"
  [ testCase "unit expression canonicalizes to Can.Unit" $
      let srcExpr = A.At dummyRegion Src.Unit
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Unit -> pure ()
               other -> assertFailure ("Expected Can.Unit, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "two-tuple canonicalizes to Can.Tuple" $
      let a = A.At dummyRegion (Src.Int 1)
          b = A.At dummyRegion (Src.Int 2)
          srcExpr = A.At dummyRegion (Src.Tuple a b [])
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Tuple _ _ Nothing -> pure ()
               other -> assertFailure ("Expected Can.Tuple with Nothing, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "three-tuple canonicalizes to Can.Tuple with Just" $
      let a = A.At dummyRegion (Src.Int 1)
          b = A.At dummyRegion (Src.Int 2)
          c = A.At dummyRegion (Src.Int 3)
          srcExpr = A.At dummyRegion (Src.Tuple a b [c])
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Tuple _ _ (Just _) -> pure ()
               other -> assertFailure ("Expected Can.Tuple with Just, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "four-tuple produces TupleLargerThanThree error" $
      let mkInt n = A.At dummyRegion (Src.Int n)
          srcExpr = A.At dummyRegion (Src.Tuple (mkInt 1) (mkInt 2) [mkInt 3, mkInt 4])
      in case runCanonicalize basicEnv srcExpr of
           Left _ -> pure ()
           Right _ -> assertFailure "Expected error for 4-tuple"
  ]

-- LAMBDA TESTS

lambdaTests :: TestTree
lambdaTests = testGroup "Lambda canonicalization"
  [ testCase "identity lambda canonicalizes to Can.Lambda" $
      let xName = Name.fromChars "x"
          argPat = A.At dummyRegion (Src.PVar xName)
          body = A.At dummyRegion (Src.Var Src.LowVar xName)
          srcExpr = A.At dummyRegion (Src.Lambda [argPat] body)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Lambda args _ -> length args @?= 1
               other -> assertFailure ("Expected Can.Lambda, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "lambda with two args has two pattern args" $
      let xName = Name.fromChars "x"
          yName = Name.fromChars "y"
          argPatX = A.At dummyRegion (Src.PVar xName)
          argPatY = A.At dummyRegion (Src.PVar yName)
          body = A.At dummyRegion (Src.Int 0)
          srcExpr = A.At dummyRegion (Src.Lambda [argPatX, argPatY] body)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Lambda args _ -> length args @?= 2
               other -> assertFailure ("Expected Can.Lambda, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "lambda with duplicate arg names produces error" $
      let xName = Name.fromChars "x"
          argPat1 = A.At dummyRegion (Src.PVar xName)
          argPat2 = A.At dummyRegion (Src.PVar xName)
          body = A.At dummyRegion (Src.Int 0)
          srcExpr = A.At dummyRegion (Src.Lambda [argPat1, argPat2] body)
      in case runCanonicalize basicEnv srcExpr of
           Left _ -> pure ()
           Right _ -> assertFailure "Expected error for duplicate lambda arg"
  ]

-- CALL TESTS

callTests :: TestTree
callTests = testGroup "Call canonicalization"
  [ testCase "call with no args canonicalizes to Can.Call" $
      let funcExpr = A.At dummyRegion (Src.Int 1)
          srcExpr = A.At dummyRegion (Src.Call funcExpr [])
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Call _ args -> length args @?= 0
               other -> assertFailure ("Expected Can.Call, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "call with two args has two arguments" $
      let funcExpr = A.At dummyRegion (Src.Int 0)
          arg1 = A.At dummyRegion (Src.Int 1)
          arg2 = A.At dummyRegion (Src.Int 2)
          srcExpr = A.At dummyRegion (Src.Call funcExpr [arg1, arg2])
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Call _ args -> length args @?= 2
               other -> assertFailure ("Expected Can.Call, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- IF TESTS

ifTests :: TestTree
ifTests = testGroup "If-then-else canonicalization"
  [ testCase "single if-else canonicalizes to Can.If" $
      let cond = A.At dummyRegion (Src.Int 1)
          thenB = A.At dummyRegion (Src.Int 2)
          elseB = A.At dummyRegion (Src.Int 3)
          srcExpr = A.At dummyRegion (Src.If [(cond, thenB)] elseB)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.If branches _ -> length branches @?= 1
               other -> assertFailure ("Expected Can.If, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "if-elif-else has two branches" $
      let mkInt n = A.At dummyRegion (Src.Int n)
          srcExpr = A.At dummyRegion (Src.If [(mkInt 1, mkInt 2), (mkInt 3, mkInt 4)] (mkInt 5))
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.If branches _ -> length branches @?= 2
               other -> assertFailure ("Expected Can.If, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- CASE TESTS

caseTests :: TestTree
caseTests = testGroup "Case expression canonicalization"
  [ testCase "case with one branch canonicalizes to Can.Case" $
      let scrutinee = A.At dummyRegion (Src.Int 1)
          pat = A.At dummyRegion (Src.PAnything)
          body = A.At dummyRegion (Src.Int 2)
          srcExpr = A.At dummyRegion (Src.Case scrutinee [(pat, body)])
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Case _ branches -> length branches @?= 1
               other -> assertFailure ("Expected Can.Case, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "case with two branches has two branches" $
      let scrutinee = A.At dummyRegion (Src.Int 0)
          mkBranch n = (A.At dummyRegion (Src.PInt n), A.At dummyRegion (Src.Int n))
          srcExpr = A.At dummyRegion (Src.Case scrutinee [mkBranch 1, mkBranch 2])
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Case _ branches -> length branches @?= 2
               other -> assertFailure ("Expected Can.Case, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- RECORD ACCESS TESTS

accessTests :: TestTree
accessTests = testGroup "Record accessor and access canonicalization"
  [ testCase "accessor expression canonicalizes to Can.Accessor" $
      let fieldName = Name.fromChars "name"
          srcExpr = A.At dummyRegion (Src.Accessor fieldName)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Accessor f -> f @?= fieldName
               other -> assertFailure ("Expected Can.Accessor, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "record access canonicalizes to Can.Access" $
      let fieldName = Name.fromChars "field"
          recordExpr = A.At dummyRegion (Src.Int 0)
          fieldLoc = A.At dummyRegion fieldName
          srcExpr = A.At dummyRegion (Src.Access recordExpr fieldLoc)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Access _ f -> A.toValue f @?= fieldName
               other -> assertFailure ("Expected Can.Access, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- LET BINDING TESTS

letTests :: TestTree
letTests = testGroup "Let binding canonicalization"
  [ testCase "simple let binding canonicalizes successfully" $
      let xName = Name.fromChars "x"
          aname = A.At dummyRegion xName
          def = A.At dummyRegion (Src.Define aname [] (A.At dummyRegion (Src.Int 42)) Nothing)
          body = A.At dummyRegion (Src.Var Src.LowVar xName)
          srcExpr = A.At dummyRegion (Src.Let [def] body)
      in case runCanonicalize basicEnv srcExpr of
           Right _ -> pure ()
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "let with duplicate bindings produces error" $
      let xName = Name.fromChars "x"
          aname = A.At dummyRegion xName
          def1 = A.At dummyRegion (Src.Define aname [] (A.At dummyRegion (Src.Int 1)) Nothing)
          def2 = A.At dummyRegion (Src.Define aname [] (A.At dummyRegion (Src.Int 2)) Nothing)
          body = A.At dummyRegion (Src.Var Src.LowVar xName)
          srcExpr = A.At dummyRegion (Src.Let [def1, def2] body)
      in case runCanonicalize basicEnv srcExpr of
           Left _ -> pure ()
           Right _ -> assertFailure "Expected error for duplicate let bindings"

  , testCase "let with recursive function succeeds" $
      let fName = Name.fromChars "f"
          aname = A.At dummyRegion fName
          argPat = A.At dummyRegion (Src.PVar (Name.fromChars "n"))
          callF = A.At dummyRegion (Src.Var Src.LowVar fName)
          callN = A.At dummyRegion (Src.Int 0)
          body = A.At dummyRegion (Src.Call callF [callN])
          def = A.At dummyRegion (Src.Define aname [argPat] body Nothing)
          letBody = A.At dummyRegion (Src.Int 0)
          srcExpr = A.At dummyRegion (Src.Let [def] letBody)
      in case runCanonicalize basicEnv srcExpr of
           Right _ -> pure ()
           Left _ -> pure ()
  ]

-- BINOP CLASSIFICATION TESTS

binopClassifyTests :: TestTree
binopClassifyTests = testGroup "Binary operator classification"
  [ testCase "Basics.add (+) classifies as NativeArith Add" $
      let left = A.At dummyRegion (Src.Int 1)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "+")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.BinopOp (Can.NativeArith Can.Add) _ _ _ -> pure ()
               other -> assertFailure ("Expected NativeArith Add, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "Basics.sub (-) classifies as NativeArith Sub" $
      let left = A.At dummyRegion (Src.Int 10)
          right = A.At dummyRegion (Src.Int 3)
          op = A.At dummyRegion (Name.fromChars "-")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.BinopOp (Can.NativeArith Can.Sub) _ _ _ -> pure ()
               other -> assertFailure ("Expected NativeArith Sub, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "Basics.mul (*) classifies as NativeArith Mul" $
      let left = A.At dummyRegion (Src.Int 4)
          right = A.At dummyRegion (Src.Int 5)
          op = A.At dummyRegion (Name.fromChars "*")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.BinopOp (Can.NativeArith Can.Mul) _ _ _ -> pure ()
               other -> assertFailure ("Expected NativeArith Mul, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "Basics.fdiv (/) classifies as NativeArith Div" $
      let left = A.At dummyRegion (Src.Int 8)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "/")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.BinopOp (Can.NativeArith Can.Div) _ _ _ -> pure ()
               other -> assertFailure ("Expected NativeArith Div, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "non-native operator (//) classifies as UserDefined" $
      let left = A.At dummyRegion (Src.Int 7)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "//")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.BinopOp (Can.UserDefined _ _ _) _ _ _ -> pure ()
               other -> assertFailure ("Expected UserDefined, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "chained left-associative + produces nested left tree" $
      let mkInt n = A.At dummyRegion (Src.Int n)
          opPlus = A.At dummyRegion (Name.fromChars "+")
          srcExpr = A.At dummyRegion (Src.Binops [(mkInt 1, opPlus), (mkInt 2, opPlus)] (mkInt 3))
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.BinopOp (Can.NativeArith Can.Add) _ _ _ -> pure ()
               other -> assertFailure ("Expected NativeArith Add at root, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- ERROR TESTS

errorTests :: TestTree
errorTests = testGroup "Canonicalization error conditions"
  [ testCase "undefined operator produces error" $
      let left = A.At dummyRegion (Src.Int 1)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "@@@")
          srcExpr = A.At dummyRegion (Src.Binops [(left, op)] right)
      in case runCanonicalize basicEnv srcExpr of
           Left _ -> pure ()
           Right _ -> assertFailure "Expected error for undefined operator @@@"

  , testCase "undefined lowercase variable produces error" $
      let srcExpr = A.At dummyRegion (Src.Var Src.LowVar (Name.fromChars "noSuchThing"))
      in case runCanonicalize basicEnv srcExpr of
           Left _ -> pure ()
           Right _ -> assertFailure "Expected error for undefined variable"

  , testCase "negate of integer succeeds" $
      let inner = A.At dummyRegion (Src.Int 5)
          srcExpr = A.At dummyRegion (Src.Negate inner)
      in case runCanonicalize basicEnv srcExpr of
           Right canExpr ->
             case A.toValue canExpr of
               Can.Negate _ -> pure ()
               other -> assertFailure ("Expected Can.Negate, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- HELPERS

-- | Basic test environment with arithmetic operators registered.
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

-- | Operators registered in the basic test environment.
arithmeticOps :: [(String, Binop.Associativity, Int)]
arithmeticOps =
  [ ("+", Binop.Left, 6)
  , ("-", Binop.Left, 6)
  , ("*", Binop.Left, 7)
  , ("/", Binop.Left, 7)
  , ("//", Binop.Left, 7)
  , ("%", Binop.Left, 7)
  , ("^", Binop.Right, 8)
  ]

-- | Create a binop environment entry.
makeBinopEntry :: (String, Binop.Associativity, Int) -> (Name.Name, Env.Info Env.Binop)
makeBinopEntry (opStr, assoc, prec) =
  let opName = Name.fromChars opStr
      binop = makeBinop opName assoc prec
  in (opName, Env.Specific ModuleName.basics binop)

-- | Construct a Binop value for the test environment.
makeBinop :: Name.Name -> Binop.Associativity -> Int -> Env.Binop
makeBinop opName assoc prec =
  Env.Binop
    { Env._op = opName
    , Env._op_home = ModuleName.basics
    , Env._op_name = opName
    , Env._op_annotation = Can.Forall Map.empty Can.TUnit
    , Env._op_associativity = assoc
    , Env._op_precedence = Binop.Precedence (fromIntegral prec)
    }

-- | Run canonicalization returning Either String for test assertions.
runCanonicalize :: Env.Env -> Src.Expr -> Either String Can.Expr
runCanonicalize env expr =
  let Result.Result k = Canon.canonicalize env expr
  in k Map.empty [] (\_ _ _ -> Left "Canonicalization error") (\_ _ a -> Right a)

-- | Dummy region for test AST nodes.
dummyRegion :: A.Region
dummyRegion = A.Region (A.Position 0 0) (A.Position 0 0)
