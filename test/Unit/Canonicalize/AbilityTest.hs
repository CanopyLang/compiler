{-# LANGUAGE OverloadedStrings #-}

-- | Tests for Canonicalize.Ability — ability and impl canonicalization.
--
-- Validates that the canonicalizer correctly transforms parsed ability and
-- impl declarations into their canonical forms, including:
--
--   * Ability name, type variable, and method extraction
--   * Impl ability reference resolution and method canonicalization
--   * Multiple methods per ability
--   * Error reporting for unknown abilities and missing/extra methods
--
-- @since 0.20.0
module Unit.Canonicalize.AbilityTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canonicalize.Module as Module
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Char8 as C8
import qualified Data.Map.Strict as Map
import qualified Parse.Module as ParseModule
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as Warning

-- | Top-level test tree for Canonicalize.Ability.
tests :: TestTree
tests =
  testGroup
    "Canonicalize.Ability Tests"
    [ abilityCanonTests
    , implCanonTests
    , multipleMethodTests
    , errorTests
    ]

-- ABILITY CANONICALIZATION TESTS

abilityCanonTests :: TestTree
abilityCanonTests =
  testGroup
    "ability canonicalization"
    [ testAbilityName
    , testAbilityVar
    , testAbilityMethodPresent
    ]

testAbilityName :: TestTree
testAbilityName = testCase "ability has correct canonical name" $ do
  canMod <- canonicalizeSource abilityShowSrc
  let abilities = Can._abilities canMod
  Map.member (Name.fromChars "Show") abilities @?= True

testAbilityVar :: TestTree
testAbilityVar = testCase "ability has correct type variable" $ do
  canMod <- canonicalizeSource abilityShowSrc
  let abilities = Can._abilities canMod
  verifyAbilityVar abilities "Show" "a"

testAbilityMethodPresent :: TestTree
testAbilityMethodPresent = testCase "ability method is present" $ do
  canMod <- canonicalizeSource abilityShowSrc
  let abilities = Can._abilities canMod
  verifyAbilityMethodCount abilities "Show" 1

-- IMPL CANONICALIZATION TESTS

implCanonTests :: TestTree
implCanonTests =
  testGroup
    "impl canonicalization"
    [ testImplCount
    , testImplAbilityRef
    , testImplMethodPresent
    ]

testImplCount :: TestTree
testImplCount = testCase "impl is present after canonicalization" $ do
  canMod <- canonicalizeSource abilityWithImplSrc
  length (Can._impls canMod) @?= 1

testImplAbilityRef :: TestTree
testImplAbilityRef = testCase "impl references correct ability" $ do
  canMod <- canonicalizeSource abilityWithImplSrc
  impl <- firstImpl canMod
  Name.toChars (Can._implAbility impl) @?= "Show"

testImplMethodPresent :: TestTree
testImplMethodPresent = testCase "impl has method definition" $ do
  canMod <- canonicalizeSource abilityWithImplSrc
  impl <- firstImpl canMod
  Map.member (Name.fromChars "show") (Can._implMethods impl) @?= True

-- MULTIPLE METHOD TESTS

multipleMethodTests :: TestTree
multipleMethodTests =
  testGroup
    "multiple methods"
    [ testMultipleAbilityMethods
    , testMultipleImplMethods
    , testMethodNamesCorrect
    ]

testMultipleAbilityMethods :: TestTree
testMultipleAbilityMethods = testCase "ability with two methods has both" $ do
  canMod <- canonicalizeSource abilityEqSrc
  let abilities = Can._abilities canMod
  verifyAbilityMethodCount abilities "Eq" 2

testMultipleImplMethods :: TestTree
testMultipleImplMethods = testCase "impl with two methods has both" $ do
  canMod <- canonicalizeSource eqWithImplSrc
  impl <- firstImpl canMod
  Map.size (Can._implMethods impl) @?= 2

testMethodNamesCorrect :: TestTree
testMethodNamesCorrect = testCase "ability method names are eq and neq" $ do
  canMod <- canonicalizeSource abilityEqSrc
  let abilities = Can._abilities canMod
  verifyAbilityMethodNames abilities "Eq" ["eq", "neq"]

-- ERROR TESTS

errorTests :: TestTree
errorTests =
  testGroup
    "error cases"
    [ testUnknownAbilityError
    , testMissingMethodError
    , testExtraMethodError
    ]

testUnknownAbilityError :: TestTree
testUnknownAbilityError = testCase "impl of unknown ability produces error" $ do
  errs <- canonicalizeSourceErrors unknownAbilitySrc
  assertErrorContains errs isUnknownAbilityError "UnknownAbility"

testMissingMethodError :: TestTree
testMissingMethodError = testCase "impl missing a method produces error" $ do
  errs <- canonicalizeSourceErrors missingMethodSrc
  assertErrorContains errs isMissingMethodError "MissingMethod"

testExtraMethodError :: TestTree
testExtraMethodError = testCase "impl with extra method produces error" $ do
  errs <- canonicalizeSourceErrors extraMethodSrc
  assertErrorContains errs isExtraMethodError "ExtraMethod"

-- SOURCE FRAGMENTS

abilityShowSrc :: String
abilityShowSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "ability Show a where"
    , "  show : a -> a"
    ]

abilityWithImplSrc :: String
abilityWithImplSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "type MyType = MyType"
    , ""
    , "ability Show a where"
    , "  show : a -> a"
    , ""
    , "impl Show MyType where"
    , "  show n ="
    , "    n"
    ]

abilityEqSrc :: String
abilityEqSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "ability Eq a where"
    , "  eq : a -> a -> a"
    , "  neq : a -> a -> a"
    ]

eqWithImplSrc :: String
eqWithImplSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "type MyType = MyType"
    , ""
    , "ability Eq a where"
    , "  eq : a -> a -> a"
    , "  neq : a -> a -> a"
    , ""
    , "impl Eq MyType where"
    , "  eq a b ="
    , "    a"
    , "  neq a b ="
    , "    b"
    ]

unknownAbilitySrc :: String
unknownAbilitySrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "type MyType = MyType"
    , ""
    , "impl Show MyType where"
    , "  show n ="
    , "    n"
    ]

missingMethodSrc :: String
missingMethodSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "type MyType = MyType"
    , ""
    , "ability Eq a where"
    , "  eq : a -> a -> a"
    , "  neq : a -> a -> a"
    , ""
    , "impl Eq MyType where"
    , "  eq a b ="
    , "    a"
    ]

extraMethodSrc :: String
extraMethodSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "type MyType = MyType"
    , ""
    , "ability Show a where"
    , "  show : a -> a"
    , ""
    , "impl Show MyType where"
    , "  show n ="
    , "    n"
    , "  extra n ="
    , "    n"
    ]

-- HELPERS

-- | Parse and canonicalize a source string, returning the canonical module.
canonicalizeSource :: String -> IO Can.Module
canonicalizeSource src = do
  modul <- parseSrc src
  let result = runCanon modul
  expectCanonRight result

-- | Parse and canonicalize a source string, returning errors on failure.
canonicalizeSourceErrors :: String -> IO [Error.Error]
canonicalizeSourceErrors src = do
  modul <- parseSrc src
  let result = runCanon modul
  expectCanonLeft result

-- | Parse a source string into a source module, failing the test on error.
parseSrc :: String -> IO Src.Module
parseSrc src =
  case ParseModule.fromByteString (ParseModule.Package Pkg.core) (C8.pack src) of
    Right m -> pure m
    Left err -> assertFailure ("parse failed: " <> show err) >> error "unreachable"

-- | Run canonicalization on a source module.
runCanon :: Src.Module -> ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) Can.Module)
runCanon modul =
  Result.run (Module.canonicalize Pkg.core (ParseModule.Package Pkg.core) Map.empty Map.empty modul)

-- | Extract a successful canonical module from a Result run.
expectCanonRight :: ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) Can.Module) -> IO Can.Module
expectCanonRight (_, Right val) = pure val
expectCanonRight (_, Left errs) =
  assertFailure ("Expected success, got errors: " <> show (flattenErrors errs)) >> error "unreachable"

-- | Extract errors from a failed Result run.
expectCanonLeft :: ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) a) -> IO [Error.Error]
expectCanonLeft (_, Left errs) = pure (flattenErrors errs)
expectCanonLeft (_, Right _) = assertFailure "Expected error, got success" >> error "unreachable"

-- | Extract the first impl from a canonical module, failing if none exist.
firstImpl :: Can.Module -> IO Can.Impl
firstImpl canMod =
  case Can._impls canMod of
    (impl : _) -> pure impl
    [] -> assertFailure "Expected at least one impl" >> error "unreachable"

-- | Flatten a OneOrMore into a list.
flattenErrors :: OneOrMore.OneOrMore Error.Error -> [Error.Error]
flattenErrors = OneOrMore.destruct (:)

-- | Verify the type variable of an ability by name.
verifyAbilityVar :: Map.Map Name.Name Can.Ability -> String -> String -> IO ()
verifyAbilityVar abilities abilityName expectedVar =
  case Map.lookup (Name.fromChars abilityName) abilities of
    Nothing -> assertFailure ("Ability " <> abilityName <> " not found")
    Just ability -> Name.toChars (Can._abilityVar ability) @?= expectedVar

-- | Verify the method count of an ability by name.
verifyAbilityMethodCount :: Map.Map Name.Name Can.Ability -> String -> Int -> IO ()
verifyAbilityMethodCount abilities abilityName expected =
  case Map.lookup (Name.fromChars abilityName) abilities of
    Nothing -> assertFailure ("Ability " <> abilityName <> " not found")
    Just ability -> Map.size (Can._abilityMethods ability) @?= expected

-- | Verify the method names of an ability match the expected list.
verifyAbilityMethodNames :: Map.Map Name.Name Can.Ability -> String -> [String] -> IO ()
verifyAbilityMethodNames abilities abilityName expected =
  case Map.lookup (Name.fromChars abilityName) abilities of
    Nothing -> assertFailure ("Ability " <> abilityName <> " not found")
    Just ability ->
      let names = fmap Name.toChars (Map.keys (Can._abilityMethods ability))
      in names @?= expected

-- | Assert that the error list contains an error matching the predicate.
assertErrorContains :: [Error.Error] -> (Error.Error -> Bool) -> String -> IO ()
assertErrorContains errs predicate label =
  assertBool
    ("Expected " <> label <> " error, got: " <> show errs)
    (any predicate errs)

-- | Check if an error is an UnknownAbility error.
isUnknownAbilityError :: Error.Error -> Bool
isUnknownAbilityError (Error.UnknownAbility _ _) = True
isUnknownAbilityError _ = False

-- | Check if an error is a MissingMethod error.
isMissingMethodError :: Error.Error -> Bool
isMissingMethodError (Error.MissingMethod _ _) = True
isMissingMethodError _ = False

-- | Check if an error is an ExtraMethod error.
isExtraMethodError :: Error.Error -> Bool
isExtraMethodError (Error.ExtraMethod _ _) = True
isExtraMethodError _ = False
