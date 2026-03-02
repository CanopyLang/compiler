module Unit.AST.CanonicalTypeTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map as Map
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "AST.Canonical Type Tests"
    [ testFieldsToListOrdering,
      testTypeConstructors,
      testAliasAndRecord,
      testExportsAndPorts,
      testAliasBounds
    ]

testFieldsToListOrdering :: TestTree
testFieldsToListOrdering = testCase "fieldsToList orders by source index" $ do
  let fields =
        Map.fromList
          [ (Name.fromChars "z", Can.FieldType 2 (Can.TVar (Name.fromChars "a"))),
            (Name.fromChars "a", Can.FieldType 0 (Can.TUnit)),
            (Name.fromChars "m", Can.FieldType 1 (Can.TVar (Name.fromChars "b")))
          ]
  let ordered = Can.fieldsToList fields
  [Name.fromChars "a", Name.fromChars "m", Name.fromChars "z"] @?= fmap fst ordered

testTypeConstructors :: TestTree
testTypeConstructors = testCase "lambda, tuple, type constructors" $ do
  let tvA = Can.TVar (Name.fromChars "a")
  let tvB = Can.TVar (Name.fromChars "b")
  case Can.TLambda tvA tvB of
    Can.TLambda _ _ -> return ()
    _ -> assertFailure "expected TLambda"
  case Can.TTuple tvA tvB Nothing of
    Can.TTuple _ _ Nothing -> return ()
    _ -> assertFailure "expected TTuple"
  let listTy = Can.TType ModuleName.list Name.list [tvA]
  case listTy of
    Can.TType _ _ [Can.TVar _] -> return ()
    _ -> assertFailure "expected list type with one param"

testAliasAndRecord :: TestTree
testAliasAndRecord = testCase "alias and record types" $ do
  let alias = Can.Alias [Name.fromChars "a"] (Can.TVar (Name.fromChars "a")) Nothing
  Can.Alias [Name.fromChars "a"] (Can.TVar (Name.fromChars "a")) Nothing @?= alias
  let rec = Can.TRecord (Map.fromList [(Name.fromChars "x", Can.FieldType 0 (Can.TUnit))]) Nothing
  case rec of
    Can.TRecord m Nothing -> Map.size m @?= 1
    _ -> assertFailure "expected simple record"

testExportsAndPorts :: TestTree
testExportsAndPorts = testCase "exports and ports data constructors" $ do
  let ex = Can.ExportEverything Ann.one
  case ex of
    Can.ExportEverything _ -> return ()
    Can.Export _ -> assertFailure "expected ExportEverything"
  let incoming = Can.Incoming Map.empty (Can.TUnit) (Can.TUnit)
  case incoming of
    Can.Incoming {} -> return ()
    Can.Outgoing {} -> assertFailure "expected Incoming"

-- | Verify that canonical Alias correctly stores supertype bounds.
testAliasBounds :: TestTree
testAliasBounds = testCase "alias supertype bounds" $ do
  let stringType = Can.TType ModuleName.basics (Name.fromChars "String") []
  let comparable = Can.Alias [] stringType (Just Can.ComparableBound)
  let appendable = Can.Alias [] stringType (Just Can.AppendableBound)
  let number = Can.Alias [] (Can.TType ModuleName.basics (Name.fromChars "Int") []) (Just Can.NumberBound)
  let compappend = Can.Alias [] stringType (Just Can.CompAppendBound)
  let unbounded = Can.Alias [] stringType Nothing
  -- Verify each bound is stored correctly
  Can.Alias [] stringType (Just Can.ComparableBound) @?= comparable
  Can.Alias [] stringType (Just Can.AppendableBound) @?= appendable
  Can.Alias [] (Can.TType ModuleName.basics (Name.fromChars "Int") []) (Just Can.NumberBound) @?= number
  Can.Alias [] stringType (Just Can.CompAppendBound) @?= compappend
  Can.Alias [] stringType Nothing @?= unbounded
  -- Verify bounds are distinct
  (Just Can.ComparableBound /= Just Can.AppendableBound) @?= True
  (Just Can.NumberBound /= Just Can.CompAppendBound) @?= True
  (Just Can.ComparableBound /= Nothing) @?= True
