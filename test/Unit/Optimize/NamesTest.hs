{-# LANGUAGE OverloadedStrings #-}

-- | Tests for Optimize.Names
--
-- Verifies the name tracking and generation system used during optimization.
-- Tests cover the Tracker monad, name generation, global registration,
-- kernel registration, field registration, and accumulation semantics.
module Unit.Optimize.NamesTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Optimize.Names as Names
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Optimize.Names"
    [ runEmptyTests,
      generateTests,
      registerGlobalTests,
      registerKernelTests,
      registerFieldTests,
      registerFieldDictTests,
      registerFieldListTests,
      accumulationTests,
      monadTests
    ]

-- HELPERS

-- | Extract the dependency set from a Tracker result.
getDeps :: Names.Tracker a -> Set Opt.Global
getDeps tracker =
  let (deps, _, _) = Names.run tracker
   in deps

-- | Extract the field map from a Tracker result.
getFields :: Names.Tracker a -> Map Name.Name Int
getFields tracker =
  let (_, fields, _) = Names.run tracker
   in fields

-- | Extract the value from a Tracker result.
getValue :: Names.Tracker a -> a
getValue tracker =
  let (_, _, value) = Names.run tracker
   in value

-- | A test canonical module name.
testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical Pkg.core (Name.fromChars "Test.Module")

-- | Another test canonical module name.
otherHome :: ModuleName.Canonical
otherHome = ModuleName.Canonical Pkg.core (Name.fromChars "Other.Module")

-- RUN EMPTY TESTS

runEmptyTests :: TestTree
runEmptyTests =
  testGroup
    "run with empty tracker"
    [ testCase "pure value produces empty dependencies" $
        getDeps (pure ()) @?= Set.empty,
      testCase "pure value produces empty fields" $
        getFields (pure ()) @?= Map.empty,
      testCase "pure value is preserved" $
        getValue (pure (42 :: Int)) @?= 42,
      testCase "pure string value is preserved" $
        getValue (pure "hello") @?= ("hello" :: String)
    ]

-- GENERATE TESTS

generateTests :: TestTree
generateTests =
  testGroup
    "generate unique names"
    [ testCase "first generate produces _v0" $
        Name.toChars (getValue Names.generate) @?= "_v0",
      testCase "second generate produces _v1" $
        let tracker = Names.generate >> Names.generate
         in Name.toChars (getValue tracker) @?= "_v1",
      testCase "sequential generates produce distinct names" $
        let tracker = do
              n0 <- Names.generate
              n1 <- Names.generate
              pure (n0, n1)
            (n0, n1) = getValue tracker
         in assertBool
              "generated names must be distinct"
              (Name.toChars n0 /= Name.toChars n1),
      testCase "generate does not add dependencies" $
        getDeps Names.generate @?= Set.empty,
      testCase "generate does not add fields" $
        getFields Names.generate @?= Map.empty
    ]

-- REGISTER GLOBAL TESTS

registerGlobalTests :: TestTree
registerGlobalTests =
  testGroup
    "registerGlobal"
    [ testCase "registerGlobal adds to dependency set" $
        let deps = getDeps (Names.registerGlobal testHome (Name.fromChars "myFunc"))
         in Set.size deps @?= 1,
      testCase "registerGlobal produces VarGlobal expression" $
        let expr = getValue (Names.registerGlobal testHome (Name.fromChars "myFunc"))
         in assertIsVarGlobal expr,
      testCase "registerGlobal does not affect fields" $
        getFields (Names.registerGlobal testHome (Name.fromChars "myFunc"))
          @?= Map.empty
    ]

-- REGISTER KERNEL TESTS

registerKernelTests :: TestTree
registerKernelTests =
  testGroup
    "registerKernel"
    [ testCase "registerKernel adds kernel dependency" $
        let deps = getDeps (Names.registerKernel (Name.fromChars "List") ())
         in Set.size deps @?= 1,
      testCase "registerKernel preserves value" $
        getValue (Names.registerKernel (Name.fromChars "List") (99 :: Int))
          @?= 99,
      testCase "registerKernel does not affect fields" $
        getFields (Names.registerKernel (Name.fromChars "Utils") ())
          @?= Map.empty
    ]

-- REGISTER FIELD TESTS

registerFieldTests :: TestTree
registerFieldTests =
  testGroup
    "registerField"
    [ testCase "registerField adds field with count 1" $
        let fields = getFields (Names.registerField (Name.fromChars "name") ())
         in Map.lookup (Name.fromChars "name") fields @?= Just 1,
      testCase "registerField preserves value" $
        getValue (Names.registerField (Name.fromChars "x") (True :: Bool))
          @?= True,
      testCase "registerField does not add dependencies" $
        getDeps (Names.registerField (Name.fromChars "x") ())
          @?= Set.empty,
      testCase "double registerField increments count to 2" $
        let tracker = do
              _ <- Names.registerField (Name.fromChars "x") ()
              Names.registerField (Name.fromChars "x") ()
            fields = getFields tracker
         in Map.lookup (Name.fromChars "x") fields @?= Just 2
    ]

-- REGISTER FIELD DICT TESTS

registerFieldDictTests :: TestTree
registerFieldDictTests =
  testGroup
    "registerFieldDict"
    [ testCase "registerFieldDict adds all fields with count 1" $
        let dict = Map.fromList [(Name.fromChars "a", "val1"), (Name.fromChars "b", "val2")]
            fields = getFields (Names.registerFieldDict dict ())
         in do
              Map.lookup (Name.fromChars "a") fields @?= Just 1
              Map.lookup (Name.fromChars "b") fields @?= Just 1,
      testCase "registerFieldDict preserves value" $
        getValue (Names.registerFieldDict Map.empty (7 :: Int)) @?= 7,
      testCase "registerFieldDict with empty map produces empty fields" $
        getFields (Names.registerFieldDict (Map.empty :: Map Name.Name Int) ())
          @?= Map.empty
    ]

-- REGISTER FIELD LIST TESTS

registerFieldListTests :: TestTree
registerFieldListTests =
  testGroup
    "registerFieldList"
    [ testCase "registerFieldList adds all fields" $
        let names = [Name.fromChars "x", Name.fromChars "y"]
            fields = getFields (Names.registerFieldList names ())
         in do
              Map.lookup (Name.fromChars "x") fields @?= Just 1
              Map.lookup (Name.fromChars "y") fields @?= Just 1,
      testCase "registerFieldList with duplicates increments counts" $
        let names = [Name.fromChars "x", Name.fromChars "x", Name.fromChars "y"]
            fields = getFields (Names.registerFieldList names ())
         in do
              Map.lookup (Name.fromChars "x") fields @?= Just 2
              Map.lookup (Name.fromChars "y") fields @?= Just 1,
      testCase "registerFieldList with empty list produces empty fields" $
        getFields (Names.registerFieldList [] ()) @?= Map.empty
    ]

-- ACCUMULATION TESTS

accumulationTests :: TestTree
accumulationTests =
  testGroup
    "multiple registrations accumulate"
    [ testCase "two globals produce two dependencies" $
        let tracker = do
              _ <- Names.registerGlobal testHome (Name.fromChars "f1")
              Names.registerGlobal otherHome (Name.fromChars "f2")
            deps = getDeps tracker
         in Set.size deps @?= 2,
      testCase "global and kernel both appear in dependencies" $
        let tracker = do
              _ <- Names.registerGlobal testHome (Name.fromChars "f1")
              Names.registerKernel (Name.fromChars "Utils") ()
            deps = getDeps tracker
         in Set.size deps @?= 2,
      testCase "field and global accumulate independently" $
        let tracker = do
              _ <- Names.registerGlobal testHome (Name.fromChars "f1")
              Names.registerField (Name.fromChars "name") ()
         in do
              Set.size (getDeps tracker) @?= 1
              Map.size (getFields tracker) @?= 1,
      testCase "generate and register both work in sequence" $
        let tracker = do
              n <- Names.generate
              _ <- Names.registerGlobal testHome (Name.fromChars "helper")
              Names.registerField (Name.fromChars "field") n
            (deps, fields, _) = Names.run tracker
         in do
              Set.size deps @?= 1
              Map.size fields @?= 1
    ]

-- MONAD TESTS

monadTests :: TestTree
monadTests =
  testGroup
    "Tracker monad laws"
    [ testCase "fmap preserves value" $
        getValue (fmap (+ (1 :: Int)) (pure 5)) @?= 6,
      testCase "bind chains correctly" $
        let tracker = Names.generate >>= \n -> pure (Name.toChars n)
         in getValue tracker @?= "_v0",
      testCase "applicative combines results" $
        let tracker = pure (,) <*> Names.generate <*> Names.generate
            (n0, n1) = getValue tracker
         in do
              Name.toChars n0 @?= "_v0"
              Name.toChars n1 @?= "_v1"
    ]

-- ASSERTION HELPERS

-- | Assert that an expression is a VarGlobal.
assertIsVarGlobal :: Opt.Expr -> Assertion
assertIsVarGlobal (Opt.VarGlobal _) = pure ()
assertIsVarGlobal other =
  assertFailure ("Expected VarGlobal but got: " ++ take 80 (show other))
