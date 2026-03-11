{-# LANGUAGE OverloadedStrings #-}

-- | Tests for HMR (Hot Module Replacement) code generation.
--
-- Verifies model type hashing, HMR code injection in dev mode,
-- and absence of HMR code in production mode.
--
-- @since 0.20.0
module Unit.Generate.HMRTest (tests) where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Generate.JavaScript.ESM.HMR as HMR
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import qualified Data.Set as Set
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests =
  testGroup
    "HMR Code Generation"
    [ modelHashTests,
      hmrInjectionTests
    ]

-- MODEL TYPE HASHING

modelHashTests :: TestTree
modelHashTests =
  testGroup
    "Model type hashing"
    [ testCase "same type produces same hash" $
        HMR.hashCanType Can.TUnit @?= HMR.hashCanType Can.TUnit,
      testCase "different types produce different hashes" $
        assertBool
          "TUnit and TVar should have different hashes"
          (HMR.hashCanType Can.TUnit /= HMR.hashCanType (Can.TVar (Name.fromChars "a"))),
      testCase "record field order does not affect hash" $
        let x = Name.fromChars "x"
            y = Name.fromChars "y"
            fields1 = Map.fromList [(x, Can.FieldType 0 intType), (y, Can.FieldType 1 intType)]
            fields2 = Map.fromList [(y, Can.FieldType 1 intType), (x, Can.FieldType 0 intType)]
         in HMR.hashCanType (Can.TRecord fields1 Nothing)
              @?= HMR.hashCanType (Can.TRecord fields2 Nothing),
      testCase "different record fields produce different hashes" $
        let fields1 = Map.fromList [(Name.fromChars "x", Can.FieldType 0 intType)]
            fields2 = Map.fromList [(Name.fromChars "y", Can.FieldType 0 intType)]
         in assertBool
              "records with different field names should differ"
              (HMR.hashCanType (Can.TRecord fields1 Nothing) /= HMR.hashCanType (Can.TRecord fields2 Nothing)),
      testCase "added field changes hash" $
        let x = Name.fromChars "x"
            y = Name.fromChars "y"
            fields1 = Map.fromList [(x, Can.FieldType 0 intType)]
            fields2 = Map.fromList [(x, Can.FieldType 0 intType), (y, Can.FieldType 1 intType)]
         in assertBool
              "adding a field should change the hash"
              (HMR.hashCanType (Can.TRecord fields1 Nothing) /= HMR.hashCanType (Can.TRecord fields2 Nothing)),
      testCase "changed field type changes hash" $
        let x = Name.fromChars "x"
            fields1 = Map.fromList [(x, Can.FieldType 0 intType)]
            fields2 = Map.fromList [(x, Can.FieldType 0 stringType)]
         in assertBool
              "changing field type should change the hash"
              (HMR.hashCanType (Can.TRecord fields1 Nothing) /= HMR.hashCanType (Can.TRecord fields2 Nothing))
    ]

-- HMR INJECTION

hmrInjectionTests :: TestTree
hmrInjectionTests =
  testGroup
    "HMR injection"
    [ testCase "no HMR items in prod mode" $
        length (HMR.generateHMRItems prodMode testMains testHome) @?= 0,
      testCase "no HMR items for Static main" $
        length (HMR.generateHMRItems devMode staticMains testHome) @?= 0,
      testCase "no HMR items for non-main module" $
        length (HMR.generateHMRItems devMode testMains otherHome) @?= 0,
      testCase "HMR items generated for Dynamic main in dev mode" $
        let items = HMR.generateHMRItems devMode testMains testHome
         in assertBool
              "should generate 4 HMR items (hash, getModel, hotSwap, accept)"
              (length items == 4)
    ]

-- HELPERS

testPkg :: Pkg.Name
testPkg = Pkg.Name (Utf8.fromChars "author") (Utf8.fromChars "project")

testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical testPkg (Name.fromChars "Main")

otherHome :: ModuleName.Canonical
otherHome = ModuleName.Canonical testPkg (Name.fromChars "Other")

intType :: Can.Type
intType = Can.TType (ModuleName.Canonical Pkg.core (Name.fromChars "Basics")) (Name.fromChars "Int") []

stringType :: Can.Type
stringType = Can.TType (ModuleName.Canonical Pkg.core (Name.fromChars "String")) (Name.fromChars "String") []

modelType :: Can.Type
modelType = Can.TRecord (Map.fromList [(Name.fromChars "count", Can.FieldType 0 intType)]) Nothing

msgType :: Can.Type
msgType = Can.TUnit

testMains :: Map ModuleName.Canonical Opt.Main
testMains = Map.singleton testHome (Opt.Dynamic modelType msgType Opt.Unit)

staticMains :: Map ModuleName.Canonical Opt.Main
staticMains = Map.singleton testHome Opt.Static

devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

prodMode :: Mode.Mode
prodMode = Mode.Prod Map.empty False False False StringPool.emptyPool Set.empty
