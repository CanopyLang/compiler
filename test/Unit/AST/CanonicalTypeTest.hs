module Unit.AST.CanonicalTypeTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Reporting.Annotation as A
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "AST.Canonical Type Tests"
    [ testFieldsToListOrdering,
      testTypeConstructors,
      testAliasAndRecord,
      testExportsAndPorts
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
  fmap fst ordered @?= [Name.fromChars "a", Name.fromChars "m", Name.fromChars "z"]

testTypeConstructors :: TestTree
testTypeConstructors = testCase "lambda, tuple, type constructors" $ do
  let tvA = Can.TVar (Name.fromChars "a")
  let tvB = Can.TVar (Name.fromChars "b")
  case Can.TLambda tvA tvB of
    Can.TLambda _ _ -> return ()
  case Can.TTuple tvA tvB Nothing of
    Can.TTuple _ _ Nothing -> return ()
  let listTy = Can.TType ModuleName.list Name.list [tvA]
  case listTy of
    Can.TType _ _ [Can.TVar _] -> return ()
    _ -> assertFailure "expected list type with one param"

testAliasAndRecord :: TestTree
testAliasAndRecord = testCase "alias and record types" $ do
  let alias = Can.Alias [Name.fromChars "a"] (Can.TVar (Name.fromChars "a"))
  alias @?= Can.Alias [Name.fromChars "a"] (Can.TVar (Name.fromChars "a"))
  let rec = Can.TRecord (Map.fromList [(Name.fromChars "x", Can.FieldType 0 (Can.TUnit))]) Nothing
  case rec of
    Can.TRecord m Nothing -> Map.size m @?= 1
    _ -> assertFailure "expected simple record"

testExportsAndPorts :: TestTree
testExportsAndPorts = testCase "exports and ports data constructors" $ do
  let ex = Can.ExportEverything A.one
  case ex of
    Can.ExportEverything _ -> return ()
  let incoming = Can.Incoming Map.empty (Can.TUnit) (Can.TUnit)
  case incoming of
    Can.Incoming {} -> return ()
