{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the Type.Instantiate module.
--
-- Verifies that 'fromSrcType' correctly transforms canonical source types
-- (AST.Canonical.Type) into internal compiler types (Type.Type.Type) by
-- resolving free type variables and mapping each source constructor to its
-- corresponding internal representation.
--
-- @since 0.19.1
module Unit.Type.InstantiateTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Type.Instantiate as Instantiate
import Type.Type (Type (..))
import qualified Type.Type as Type
import Test.Tasty
import Test.Tasty.HUnit

-- CONSTRUCTOR PREDICATES

isUnitN :: Type -> Bool
isUnitN UnitN = True
isUnitN _ = False

isFunN :: Type -> Bool
isFunN (FunN _ _) = True
isFunN _ = False

isAppN :: Type -> Bool
isAppN (AppN _ _ _) = True
isAppN _ = False

isTupleN :: Type -> Bool
isTupleN (TupleN _ _ _) = True
isTupleN _ = False

isRecordN :: Type -> Bool
isRecordN (RecordN _ _) = True
isRecordN _ = False

isAliasN :: Type -> Bool
isAliasN (AliasN _ _ _ _) = True
isAliasN _ = False

-- TEST TREE

tests :: TestTree
tests =
  testGroup
    "Type.Instantiate Tests"
    [ testTUnitProducesUnitN,
      testTTypeNoArgsProducesAppN,
      testTTypeWithArgsProducesAppN,
      testTLambdaProducesFunN,
      testTTupleNoThirdProducesTupleN,
      testTTupleWithThirdProducesTupleN,
      testTVarResolvesFromFreeVars,
      testTRecordWithFieldsProducesRecordN,
      testTRecordWithExtensionVarResolves,
      testTAliasFilledProducesAliasN
    ]

-- INDIVIDUAL TESTS

testTUnitProducesUnitN :: TestTree
testTUnitProducesUnitN = testCase "TUnit produces UnitN" $ do
  result <- Instantiate.fromSrcType Map.empty Can.TUnit
  assertBool "expected UnitN" (isUnitN result)

testTTypeNoArgsProducesAppN :: TestTree
testTTypeNoArgsProducesAppN = testCase "TType with no args produces AppN" $ do
  result <- Instantiate.fromSrcType Map.empty (Can.TType home typeName [])
  assertBool "expected AppN" (isAppN result)
  assertAppN home typeName [] result
  where
    home = ModuleName.basics
    typeName = Name.fromChars "Int"

testTTypeWithArgsProducesAppN :: TestTree
testTTypeWithArgsProducesAppN = testCase "TType with args produces AppN with transformed args" $ do
  result <- Instantiate.fromSrcType Map.empty (Can.TType home typeName [Can.TUnit, Can.TUnit])
  assertBool "expected AppN" (isAppN result)
  assertAppNArgCount 2 result
  where
    home = ModuleName.list
    typeName = Name.fromChars "List"

testTLambdaProducesFunN :: TestTree
testTLambdaProducesFunN = testCase "TLambda produces FunN" $ do
  result <- Instantiate.fromSrcType Map.empty (Can.TLambda Can.TUnit Can.TUnit)
  assertBool "expected FunN" (isFunN result)
  assertFunNComponents result

testTTupleNoThirdProducesTupleN :: TestTree
testTTupleNoThirdProducesTupleN = testCase "TTuple a b Nothing produces TupleN with Nothing" $ do
  result <- Instantiate.fromSrcType Map.empty (Can.TTuple Can.TUnit Can.TUnit Nothing)
  assertBool "expected TupleN" (isTupleN result)
  assertTupleNThird Nothing result

testTTupleWithThirdProducesTupleN :: TestTree
testTTupleWithThirdProducesTupleN = testCase "TTuple a b (Just c) produces TupleN with Just" $ do
  result <- Instantiate.fromSrcType Map.empty (Can.TTuple Can.TUnit Can.TUnit (Just Can.TUnit))
  assertBool "expected TupleN" (isTupleN result)
  assertTupleNHasThird result

testTVarResolvesFromFreeVars :: TestTree
testTVarResolvesFromFreeVars = testCase "TVar with name in freeVars resolves to mapped type" $ do
  result <- Instantiate.fromSrcType freeVars (Can.TVar varName)
  assertBool "expected AppN (resolved to int)" (isAppN result)
  assertAppN ModuleName.basics (Name.fromChars "Int") [] result
  where
    varName = Name.fromChars "a"
    freeVars = Map.singleton varName Type.int

testTRecordWithFieldsProducesRecordN :: TestTree
testTRecordWithFieldsProducesRecordN = testCase "TRecord with fields produces RecordN" $ do
  result <- Instantiate.fromSrcType Map.empty srcRecord
  assertBool "expected RecordN" (isRecordN result)
  assertRecordNFieldCount 2 result
  where
    srcRecord =
      Can.TRecord
        (Map.fromList
          [ (Name.fromChars "x", Can.FieldType 0 Can.TUnit),
            (Name.fromChars "y", Can.FieldType 1 Can.TUnit)
          ])
        Nothing

testTRecordWithExtensionVarResolves :: TestTree
testTRecordWithExtensionVarResolves = testCase "TRecord with extension var resolves extension" $ do
  result <- Instantiate.fromSrcType freeVars srcRecord
  assertBool "expected RecordN" (isRecordN result)
  assertRecordNExtIsNotEmpty result
  where
    extName = Name.fromChars "r"
    freeVars = Map.singleton extName (RecordN Map.empty EmptyRecordN)
    srcRecord =
      Can.TRecord
        (Map.fromList
          [ (Name.fromChars "x", Can.FieldType 0 Can.TUnit)
          ])
        (Just extName)

testTAliasFilledProducesAliasN :: TestTree
testTAliasFilledProducesAliasN = testCase "TAlias with Filled produces AliasN" $ do
  result <- Instantiate.fromSrcType Map.empty srcAlias
  assertBool "expected AliasN" (isAliasN result)
  assertAliasNHome ModuleName.basics result
  where
    srcAlias =
      Can.TAlias
        ModuleName.basics
        (Name.fromChars "MyAlias")
        []
        (Can.Filled Can.TUnit)

-- ASSERTION HELPERS

assertAppN :: ModuleName.Canonical -> Name.Name -> [Type] -> Type -> Assertion
assertAppN expectedHome expectedName expectedArgs (AppN actualHome actualName actualArgs) = do
  expectedHome @?= actualHome
  expectedName @?= actualName
  length expectedArgs @?= length actualArgs
assertAppN _ _ _ other =
  assertFailure ("expected AppN, got: " ++ showConstructor other)

assertAppNArgCount :: Int -> Type -> Assertion
assertAppNArgCount expected (AppN _ _ args) =
  expected @?= length args
assertAppNArgCount _ other =
  assertFailure ("expected AppN, got: " ++ showConstructor other)

assertFunNComponents :: Type -> Assertion
assertFunNComponents (FunN arg res) = do
  assertBool "arg should be UnitN" (isUnitN arg)
  assertBool "result should be UnitN" (isUnitN res)
assertFunNComponents other =
  assertFailure ("expected FunN, got: " ++ showConstructor other)

assertTupleNThird :: Maybe () -> Type -> Assertion
assertTupleNThird Nothing (TupleN _ _ Nothing) = return ()
assertTupleNThird (Just ()) (TupleN _ _ (Just _)) = return ()
assertTupleNThird Nothing (TupleN _ _ (Just _)) =
  assertFailure "expected TupleN with Nothing third, got Just"
assertTupleNThird (Just ()) (TupleN _ _ Nothing) =
  assertFailure "expected TupleN with Just third, got Nothing"
assertTupleNThird _ other =
  assertFailure ("expected TupleN, got: " ++ showConstructor other)

assertTupleNHasThird :: Type -> Assertion
assertTupleNHasThird (TupleN _ _ (Just _)) = return ()
assertTupleNHasThird (TupleN _ _ Nothing) =
  assertFailure "expected TupleN with Just third element"
assertTupleNHasThird other =
  assertFailure ("expected TupleN, got: " ++ showConstructor other)

assertRecordNFieldCount :: Int -> Type -> Assertion
assertRecordNFieldCount expected (RecordN fields _) =
  expected @?= Map.size fields
assertRecordNFieldCount _ other =
  assertFailure ("expected RecordN, got: " ++ showConstructor other)

assertRecordNExtIsNotEmpty :: Type -> Assertion
assertRecordNExtIsNotEmpty (RecordN _ ext) =
  assertBool "extension should not be EmptyRecordN" (not (isEmptyRecordN ext))
  where
    isEmptyRecordN EmptyRecordN = True
    isEmptyRecordN _ = False
assertRecordNExtIsNotEmpty other =
  assertFailure ("expected RecordN, got: " ++ showConstructor other)

assertAliasNHome :: ModuleName.Canonical -> Type -> Assertion
assertAliasNHome expectedHome (AliasN actualHome _ _ _) =
  expectedHome @?= actualHome
assertAliasNHome _ other =
  assertFailure ("expected AliasN, got: " ++ showConstructor other)

showConstructor :: Type -> String
showConstructor (PlaceHolder _) = "PlaceHolder"
showConstructor (AliasN _ _ _ _) = "AliasN"
showConstructor (VarN _) = "VarN"
showConstructor (AppN _ _ _) = "AppN"
showConstructor (FunN _ _) = "FunN"
showConstructor EmptyRecordN = "EmptyRecordN"
showConstructor (RecordN _ _) = "RecordN"
showConstructor UnitN = "UnitN"
showConstructor (TupleN _ _ _) = "TupleN"
