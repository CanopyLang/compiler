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
import qualified Reporting.Annotation as Ann
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
    , duplicateDetectionTests
    , multiAbilityModuleTests
    , abilityMethodCallTests
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

-- DUPLICATE DETECTION TESTS

duplicateDetectionTests :: TestTree
duplicateDetectionTests =
  testGroup
    "duplicate detection"
    [ testDuplicateAbilityError
    , testDuplicateImplError
    ]

testDuplicateAbilityError :: TestTree
testDuplicateAbilityError = testCase "duplicate ability names produce error" $ do
  errs <- canonicalizeSourceErrors duplicateAbilitySrc
  assertBool
    ("Expected error for duplicate abilities, got: " <> show errs)
    (not (null errs))

testDuplicateImplError :: TestTree
testDuplicateImplError = testCase "duplicate impl for same ability+type produces error" $ do
  errs <- canonicalizeSourceErrors duplicateImplSrc
  assertErrorContains errs isDuplicateImplError "DuplicateImpl"

-- MULTI-ABILITY MODULE TESTS

multiAbilityModuleTests :: TestTree
multiAbilityModuleTests =
  testGroup
    "multiple abilities in module"
    [ testTwoAbilitiesPresent
    , testTwoImplsPresent
    , testImplTypesCorrect
    ]

testTwoAbilitiesPresent :: TestTree
testTwoAbilitiesPresent = testCase "module with two abilities has both" $ do
  canMod <- canonicalizeSource twoAbilitiesSrc
  Map.size (Can._abilities canMod) @?= 2

testTwoImplsPresent :: TestTree
testTwoImplsPresent = testCase "module with two impls has both" $ do
  canMod <- canonicalizeSource twoImplsSrc
  length (Can._impls canMod) @?= 2

testImplTypesCorrect :: TestTree
testImplTypesCorrect = testCase "impls reference correct abilities" $ do
  canMod <- canonicalizeSource twoImplsSrc
  let abilityNames = fmap (Name.toChars . Can._implAbility) (Can._impls canMod)
  assertBool "Show impl present" ("Show" `elem` abilityNames)
  assertBool "Eq impl present" ("Eq" `elem` abilityNames)

-- ABILITY METHOD CALL TESTS

abilityMethodCallTests :: TestTree
abilityMethodCallTests =
  testGroup
    "AbilityMethodCall generation"
    [ testMethodCallInBody
    , testMethodAvailableInValues
    ]

testMethodCallInBody :: TestTree
testMethodCallInBody = testCase "ability method in value body produces AbilityMethodCall" $ do
  canMod <- canonicalizeSource abilityMethodUseSrc
  let hasAbilityCall = declsContainAbilityMethodCall (Can._decls canMod)
  assertBool "expected AbilityMethodCall in canonical decls" hasAbilityCall

testMethodAvailableInValues :: TestTree
testMethodAvailableInValues = testCase "ability method is resolvable in value definitions" $ do
  canMod <- canonicalizeSource abilityMethodUseSrc
  let declCount = countDecls (Can._decls canMod)
  assertBool "module has at least one declaration" (declCount > 0)

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

duplicateAbilitySrc :: String
duplicateAbilitySrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "ability Show a where"
    , "  show : a -> a"
    , ""
    , "ability Show a where"
    , "  show : a -> a"
    ]

duplicateImplSrc :: String
duplicateImplSrc =
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
    , ""
    , "impl Show MyType where"
    , "  show n ="
    , "    n"
    ]

twoAbilitiesSrc :: String
twoAbilitiesSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "ability Show a where"
    , "  show : a -> a"
    , ""
    , "ability Eq a where"
    , "  eq : a -> a -> a"
    ]

twoImplsSrc :: String
twoImplsSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "type MyType = MyType"
    , ""
    , "ability Show a where"
    , "  show : a -> a"
    , ""
    , "ability Eq a where"
    , "  eq : a -> a -> a"
    , ""
    , "impl Show MyType where"
    , "  show n ="
    , "    n"
    , ""
    , "impl Eq MyType where"
    , "  eq a b ="
    , "    a"
    ]

abilityMethodUseSrc :: String
abilityMethodUseSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "ability Show a where"
    , "  show : a -> a"
    , ""
    , "useShow x ="
    , "  show x"
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
isMissingMethodError (Error.MissingMethod _ _ _) = True
isMissingMethodError _ = False

-- | Check if an error is an ExtraMethod error.
isExtraMethodError :: Error.Error -> Bool
isExtraMethodError (Error.ExtraMethod _ _ _) = True
isExtraMethodError _ = False

-- | Check if an error is a DuplicateAbility error.
isDuplicateAbilityError :: Error.Error -> Bool
isDuplicateAbilityError (Error.DuplicateAbility _ _ _) = True
isDuplicateAbilityError _ = False

-- | Check if an error is a DuplicateImpl error.
isDuplicateImplError :: Error.Error -> Bool
isDuplicateImplError (Error.DuplicateImpl _ _ _ _) = True
isDuplicateImplError _ = False

-- | Check if canonical declarations contain an AbilityMethodCall node.
declsContainAbilityMethodCall :: Can.Decls -> Bool
declsContainAbilityMethodCall decls =
  case decls of
    Can.Declare def rest ->
      defContainsAbilityMethodCall def || declsContainAbilityMethodCall rest
    Can.DeclareRec def defs rest ->
      defContainsAbilityMethodCall def
        || any defContainsAbilityMethodCall defs
        || declsContainAbilityMethodCall rest
    Can.SaveTheEnvironment -> False

-- | Check if a Def body contains an AbilityMethodCall.
defContainsAbilityMethodCall :: Can.Def -> Bool
defContainsAbilityMethodCall (Can.Def _ _ body) = exprContainsAbilityMethodCall body
defContainsAbilityMethodCall (Can.TypedDef _ _ _ body _) = exprContainsAbilityMethodCall body

-- | Recursively check if an expression contains AbilityMethodCall.
exprContainsAbilityMethodCall :: Can.Expr -> Bool
exprContainsAbilityMethodCall (Ann.At _ expr) =
  case expr of
    Can.AbilityMethodCall _ _ _ _ -> True
    Can.Call func args ->
      exprContainsAbilityMethodCall func || any exprContainsAbilityMethodCall args
    Can.Lambda _ body -> exprContainsAbilityMethodCall body
    Can.If branches finally ->
      any (\(c, b) -> exprContainsAbilityMethodCall c || exprContainsAbilityMethodCall b) branches
        || exprContainsAbilityMethodCall finally
    Can.Let def body ->
      defContainsAbilityMethodCall def || exprContainsAbilityMethodCall body
    Can.LetRec defs body ->
      any defContainsAbilityMethodCall defs || exprContainsAbilityMethodCall body
    Can.LetDestruct _ e body ->
      exprContainsAbilityMethodCall e || exprContainsAbilityMethodCall body
    Can.Case e branches ->
      exprContainsAbilityMethodCall e
        || any (\(Can.CaseBranch _ b) -> exprContainsAbilityMethodCall b) branches
    Can.List es -> any exprContainsAbilityMethodCall es
    Can.Negate e -> exprContainsAbilityMethodCall e
    Can.BinopOp _ _ left right ->
      exprContainsAbilityMethodCall left || exprContainsAbilityMethodCall right
    Can.Access e _ -> exprContainsAbilityMethodCall e
    Can.Tuple a b mc ->
      exprContainsAbilityMethodCall a
        || exprContainsAbilityMethodCall b
        || maybe False exprContainsAbilityMethodCall mc
    _ -> False

-- | Count declarations in a Decls chain.
countDecls :: Can.Decls -> Int
countDecls Can.SaveTheEnvironment = 0
countDecls (Can.Declare _ rest) = 1 + countDecls rest
countDecls (Can.DeclareRec _ defs rest) = 1 + length defs + countDecls rest
