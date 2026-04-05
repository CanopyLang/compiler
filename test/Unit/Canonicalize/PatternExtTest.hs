{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Canonicalize.PatternExtTest - Extended tests for Canonicalize.Pattern
--
-- Covers all pattern forms handled by 'Canonicalize.Pattern.canonicalize':
-- PAnything, PVar, PRecord, PUnit, PTuple, PList, PCons, PAlias, PChr, PStr, PInt.
-- Also tests the verify function under various contexts.
--
-- @since 0.19.1
module Unit.Canonicalize.PatternExtTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified AST.Source as Src
import qualified AST.Canonical as Can
import qualified Canonicalize.Pattern as Pattern
import qualified Canonicalize.Environment as Env
import qualified Canopy.ModuleName as ModuleName
import qualified Reporting.Annotation as A
import qualified Canonicalize.Environment.Dups as Dups
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Canopy.Data.OneOrMore as OneOrMore

-- | Main test tree.
tests :: TestTree
tests = testGroup "Canonicalize.Pattern Extended Tests"
  [ wildcardPatternTests
  , varPatternTests
  , literalPatternTests
  , tuplePatternTests
  , listPatternTests
  , consPatternTests
  , aliasPatternTests
  , recordPatternTests
  , unitPatternTests
  ]

-- WILDCARD PATTERN

wildcardPatternTests :: TestTree
wildcardPatternTests = testGroup "PAnything pattern"
  [ testCase "PAnything canonicalizes to Can.PAnything" $
      let pat = A.At dummyRegion Src.PAnything
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PAnything -> pure ()
               other -> assertFailure ("Expected PAnything, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "PAnything does not introduce bindings" $
      let pat = A.At dummyRegion Src.PAnything
      in case runVerify emptyEnv pat of
           Right (_, bindings) -> Map.size bindings @?= 0
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- VAR PATTERN

varPatternTests :: TestTree
varPatternTests = testGroup "PVar pattern"
  [ testCase "PVar canonicalizes to Can.PVar with same name" $
      let xName = Name.fromChars "x"
          pat = A.At dummyRegion (Src.PVar xName)
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PVar n -> n @?= xName
               other -> assertFailure ("Expected PVar, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "PVar introduces one binding" $
      let pat = A.At dummyRegion (Src.PVar (Name.fromChars "myVar"))
      in case runVerify emptyEnv pat of
           Right (_, bindings) -> Map.size bindings @?= 1
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "PVar binding key matches variable name" $
      let xName = Name.fromChars "result"
          pat = A.At dummyRegion (Src.PVar xName)
      in case runVerify emptyEnv pat of
           Right (_, bindings) -> Map.member xName bindings @?= True
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- LITERAL PATTERNS

literalPatternTests :: TestTree
literalPatternTests = testGroup "Literal patterns"
  [ testCase "PChr canonicalizes to Can.PChr" $
      let chrVal = Utf8.fromChars "a"
          pat = A.At dummyRegion (Src.PChr chrVal)
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PChr _ -> pure ()
               other -> assertFailure ("Expected PChr, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "PStr canonicalizes to Can.PStr" $
      let strVal = Utf8.fromChars "hello"
          pat = A.At dummyRegion (Src.PStr strVal)
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PStr _ -> pure ()
               other -> assertFailure ("Expected PStr, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "PInt canonicalizes to Can.PInt with correct value" $
      let pat = A.At dummyRegion (Src.PInt 42)
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PInt n -> n @?= 42
               other -> assertFailure ("Expected PInt, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "literal patterns introduce no bindings" $
      let pat = A.At dummyRegion (Src.PInt 0)
      in case runVerify emptyEnv pat of
           Right (_, bindings) -> Map.size bindings @?= 0
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- TUPLE PATTERN

tuplePatternTests :: TestTree
tuplePatternTests = testGroup "PTuple pattern"
  [ testCase "two-element tuple pattern produces Can.PTuple with Nothing" $
      let a = A.At dummyRegion (Src.PVar (Name.fromChars "a"))
          b = A.At dummyRegion (Src.PVar (Name.fromChars "b"))
          pat = A.At dummyRegion (Src.PTuple a b [])
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PTuple _ _ Nothing -> pure ()
               other -> assertFailure ("Expected PTuple with Nothing, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "three-element tuple pattern produces Can.PTuple with Just" $
      let mkVar n = A.At dummyRegion (Src.PVar (Name.fromChars n))
          pat = A.At dummyRegion (Src.PTuple (mkVar "a") (mkVar "b") [mkVar "c"])
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PTuple _ _ (Just _) -> pure ()
               other -> assertFailure ("Expected PTuple with Just, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "four-element tuple produces TupleLargerThanThree error" $
      let mkVar n = A.At dummyRegion (Src.PVar (Name.fromChars n))
          pat = A.At dummyRegion (Src.PTuple (mkVar "a") (mkVar "b") [mkVar "c", mkVar "d"])
      in case runCanonicalizePattern emptyEnv pat of
           Left _ -> pure ()
           Right _ -> assertFailure "Expected error for 4-element tuple pattern"

  , testCase "tuple pattern bindings include all element variables" $
      let a = A.At dummyRegion (Src.PVar (Name.fromChars "x"))
          b = A.At dummyRegion (Src.PVar (Name.fromChars "y"))
          pat = A.At dummyRegion (Src.PTuple a b [])
      in case runVerify emptyEnv pat of
           Right (_, bindings) -> Map.size bindings @?= 2
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- LIST PATTERN

listPatternTests :: TestTree
listPatternTests = testGroup "PList pattern"
  [ testCase "empty list pattern canonicalizes to Can.PList []" $
      let pat = A.At dummyRegion (Src.PList [])
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PList items -> length items @?= 0
               other -> assertFailure ("Expected PList, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "list pattern with two elements has length 2" $
      let p1 = A.At dummyRegion (Src.PVar (Name.fromChars "a"))
          p2 = A.At dummyRegion (Src.PVar (Name.fromChars "b"))
          pat = A.At dummyRegion (Src.PList [p1, p2])
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PList items -> length items @?= 2
               other -> assertFailure ("Expected PList, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- CONS PATTERN

consPatternTests :: TestTree
consPatternTests = testGroup "PCons pattern"
  [ testCase "cons pattern canonicalizes to Can.PCons" $
      let hd = A.At dummyRegion (Src.PVar (Name.fromChars "h"))
          tl = A.At dummyRegion (Src.PVar (Name.fromChars "t"))
          pat = A.At dummyRegion (Src.PCons hd tl)
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PCons _ _ -> pure ()
               other -> assertFailure ("Expected PCons, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "cons pattern introduces bindings for head and tail" $
      let hd = A.At dummyRegion (Src.PVar (Name.fromChars "h"))
          tl = A.At dummyRegion (Src.PVar (Name.fromChars "t"))
          pat = A.At dummyRegion (Src.PCons hd tl)
      in case runVerify emptyEnv pat of
           Right (_, bindings) -> Map.size bindings @?= 2
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- ALIAS PATTERN

aliasPatternTests :: TestTree
aliasPatternTests = testGroup "PAlias pattern"
  [ testCase "alias pattern canonicalizes to Can.PAlias" $
      let inner = A.At dummyRegion Src.PAnything
          aliasName = A.At dummyRegion (Name.fromChars "whole")
          pat = A.At dummyRegion (Src.PAlias inner aliasName)
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PAlias _ n -> n @?= Name.fromChars "whole"
               other -> assertFailure ("Expected PAlias, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "alias pattern introduces binding for alias name" $
      let inner = A.At dummyRegion Src.PAnything
          aliasName = A.At dummyRegion (Name.fromChars "asWhole")
          pat = A.At dummyRegion (Src.PAlias inner aliasName)
      in case runVerify emptyEnv pat of
           Right (_, bindings) ->
             Map.member (Name.fromChars "asWhole") bindings @?= True
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "alias of var pattern introduces both bindings" $
      let inner = A.At dummyRegion (Src.PVar (Name.fromChars "x"))
          aliasName = A.At dummyRegion (Name.fromChars "whole")
          pat = A.At dummyRegion (Src.PAlias inner aliasName)
      in case runVerify emptyEnv pat of
           Right (_, bindings) -> Map.size bindings @?= 2
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- RECORD PATTERN

recordPatternTests :: TestTree
recordPatternTests = testGroup "PRecord pattern"
  [ testCase "record pattern with one field canonicalizes to Can.PRecord" $
      let fieldName = A.At dummyRegion (Name.fromChars "name")
          pat = A.At dummyRegion (Src.PRecord [fieldName])
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PRecord fields -> length fields @?= 1
               other -> assertFailure ("Expected PRecord, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "record pattern introduces bindings for each field" $
      let f1 = A.At dummyRegion (Name.fromChars "x")
          f2 = A.At dummyRegion (Name.fromChars "y")
          pat = A.At dummyRegion (Src.PRecord [f1, f2])
      in case runVerify emptyEnv pat of
           Right (_, bindings) -> Map.size bindings @?= 2
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- UNIT PATTERN

unitPatternTests :: TestTree
unitPatternTests = testGroup "PUnit pattern"
  [ testCase "PUnit canonicalizes to Can.PUnit" $
      let pat = A.At dummyRegion Src.PUnit
      in case runCanonicalizePattern emptyEnv pat of
           Right canPat ->
             case A.toValue canPat of
               Can.PUnit -> pure ()
               other -> assertFailure ("Expected PUnit, got: " ++ show other)
           Left err -> assertFailure ("Unexpected error: " ++ err)

  , testCase "PUnit introduces no bindings" $
      let pat = A.At dummyRegion Src.PUnit
      in case runVerify emptyEnv pat of
           Right (_, bindings) -> Map.size bindings @?= 0
           Left err -> assertFailure ("Unexpected error: " ++ err)
  ]

-- HELPERS

-- | Empty environment with no variables, types, or operators.
emptyEnv :: Env.Env
emptyEnv =
  Env.Env
    { Env._home = ModuleName.basics
    , Env._vars = Map.empty
    , Env._types = Map.empty
    , Env._ctors = Map.empty
    , Env._binops = Map.empty
    , Env._q_vars = Map.empty
    , Env._q_types = Map.empty
    , Env._q_ctors = Map.empty
    }

-- | Run pattern canonicalization returning Either for tests.
runCanonicalizePattern :: Env.Env -> Src.Pattern -> Either String Can.Pattern
runCanonicalizePattern env pat =
  let Result.Result k = Pattern.canonicalize env pat
  in k Dups.none [] (\_ _ _ -> Left "Error") (\_ _ a -> Right a)

-- | Run verify with a single pattern.
runVerify :: Env.Env -> Src.Pattern -> Either String (Can.Pattern, Pattern.Bindings)
runVerify env pat =
  let inner = Pattern.canonicalize env pat
      Result.Result k = Pattern.verify Error.DPCaseBranch inner
  in k () [] (\_ _ _ -> Left "Error") (\_ _ a -> Right a)

-- | Dummy region for test AST nodes.
dummyRegion :: A.Region
dummyRegion = A.Region (A.Position 0 0) (A.Position 0 0)
