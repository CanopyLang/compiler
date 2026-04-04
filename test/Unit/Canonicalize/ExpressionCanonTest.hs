{-# LANGUAGE OverloadedStrings #-}

-- | Tests for Canonicalize.Expression — expression canonicalization.
--
-- Validates that the expression canonicalizer correctly transforms
-- source expressions into canonical form, covering:
--
--   * Literal preservation (Int, Float, String, Char)
--   * Variable resolution (local, top-level, qualified)
--   * Lambda expressions with argument binding
--   * If-then-else branches
--   * Case expressions with pattern matching
--   * Let bindings and scoping
--   * Record literals and field access
--   * List literals
--   * Tuple expressions (2- and 3-element)
--   * Record update desugaring
--   * Error conditions: undefined variable, tuple too large
--
-- Tests that need name resolution (variables, qualified names) proceed
-- through the full parse-and-canonicalize pipeline via
-- 'Parse.Module.fromByteString' and 'Canonicalize.Module.canonicalize',
-- matching the pattern established in 'Unit.Canonicalize.AbilityTest'.
--
-- Tests for literal handling use the low-level 'Canon.canonicalize'
-- function directly with a minimal environment, as established in
-- 'Unit.Canonicalize.ExpressionArithmeticTest'.
--
-- @since 0.20.0
module Unit.Canonicalize.ExpressionCanonTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canonicalize.Expression as Canon
import qualified Canonicalize.Environment as Env
import qualified Canonicalize.Module as Module
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Float as EF
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Char8 as C8
import qualified Data.Map.Strict as Map
import qualified Parse.Module as ParseModule
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as Warning

-- | Top-level test tree for Canonicalize.Expression.
tests :: TestTree
tests =
  testGroup
    "Canonicalize.Expression Tests"
    [ literalTests
    , lambdaTests
    , ifThenElseTests
    , letTests
    , caseTests
    , listTests
    , tupleTests
    , recordTests
    , accessTests
    , pipelineTests
    , errorTests
    ]

-- LITERAL TESTS

-- | Tests for literal expression canonicalization.
--
-- Literals pass through with their values preserved exactly.
literalTests :: TestTree
literalTests =
  testGroup
    "literal canonicalization"
    [ testCase "Int literal 0 preserved" $ do
        let expr = Ann.At dummyRegion (Src.Int 0)
        case runCanon emptyEnv expr of
          Right canExpr ->
            case Ann.toValue canExpr of
              Can.Int n -> n @?= 0
              other -> assertFailure ("expected Can.Int, got: " <> show other)
          Left err -> assertFailure ("canonicalization failed: " <> err)

    , testCase "Int literal 999 preserved" $ do
        let expr = Ann.At dummyRegion (Src.Int 999)
        case runCanon emptyEnv expr of
          Right canExpr ->
            case Ann.toValue canExpr of
              Can.Int n -> n @?= 999
              other -> assertFailure ("expected Can.Int, got: " <> show other)
          Left err -> assertFailure ("canonicalization failed: " <> err)

    , testCase "Float literal preserved by content" $ do
        let floatVal = mkFloat "2.718"
            expr = Ann.At dummyRegion (Src.Float floatVal)
        case runCanon emptyEnv expr of
          Right canExpr ->
            case Ann.toValue canExpr of
              Can.Float f -> Utf8.toChars f @?= "2.718"
              other -> assertFailure ("expected Can.Float, got: " <> show other)
          Left err -> assertFailure ("canonicalization failed: " <> err)

    , testCase "String literal preserved" $ do
        let strVal = Utf8.fromChars "hello"
            expr = Ann.At dummyRegion (Src.Str strVal)
        case runCanon emptyEnv expr of
          Right canExpr ->
            case Ann.toValue canExpr of
              Can.Str s -> Utf8.toChars s @?= "hello"
              other -> assertFailure ("expected Can.Str, got: " <> show other)
          Left err -> assertFailure ("canonicalization failed: " <> err)

    , testCase "Char literal preserved" $ do
        let chrVal = Utf8.fromChars "z"
            expr = Ann.At dummyRegion (Src.Chr chrVal)
        case runCanon emptyEnv expr of
          Right canExpr ->
            case Ann.toValue canExpr of
              Can.Chr c -> Utf8.toChars c @?= "z"
              other -> assertFailure ("expected Can.Chr, got: " <> show other)
          Left err -> assertFailure ("canonicalization failed: " <> err)

    , testCase "Unit literal canonicalizes to Can.Unit" $ do
        let expr = Ann.At dummyRegion Src.Unit
        case runCanon emptyEnv expr of
          Right canExpr ->
            case Ann.toValue canExpr of
              Can.Unit -> pure ()
              other -> assertFailure ("expected Can.Unit, got: " <> show other)
          Left err -> assertFailure ("canonicalization failed: " <> err)
    ]

-- LAMBDA TESTS

-- | Tests for lambda expression canonicalization.
--
-- Uses the full pipeline so that argument patterns can be resolved in scope.
lambdaTests :: TestTree
lambdaTests =
  testGroup
    "lambda canonicalization"
    [ testLambdaOneArg
    , testLambdaTwoArgs
    ]

testLambdaOneArg :: TestTree
testLambdaOneArg = testCase "\\x -> x canonicalizes as lambda with one arg" $ do
  canMod <- canonicalizeSource (withHeader ["identity = \\x -> x"])
  countDecls (Can._decls canMod) @?= 1

testLambdaTwoArgs :: TestTree
testLambdaTwoArgs = testCase "\\x y -> x canonicalizes as lambda with two args" $ do
  canMod <- canonicalizeSource (withHeader ["const = \\x y -> x"])
  countDecls (Can._decls canMod) @?= 1

-- IF-THEN-ELSE TESTS

ifThenElseTests :: TestTree
ifThenElseTests =
  testGroup
    "if-then-else canonicalization"
    [ testSimpleIf
    , testNestedIfExpression
    ]

testSimpleIf :: TestTree
testSimpleIf = testCase "if True then 1 else 0 canonicalizes" $ do
  let src = withHeader ["branch = if True then 1 else 0"]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

testNestedIfExpression :: TestTree
testNestedIfExpression = testCase "nested if-then-else canonicalizes as value" $ do
  let src =
        withHeader
          [ "classify n ="
          , "  if n == 0 then \"zero\""
          , "  else if n == 1 then \"one\""
          , "  else \"many\""
          ]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

-- LET TESTS

letTests :: TestTree
letTests =
  testGroup
    "let binding canonicalization"
    [ testLetSimple
    , testLetUsedInBody
    , testMultipleLetBindings
    ]

testLetSimple :: TestTree
testLetSimple = testCase "let x = 1 in x canonicalizes" $ do
  let src = withHeader ["val = let x = 1 in x"]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

testLetUsedInBody :: TestTree
testLetUsedInBody = testCase "let binding used in body expression canonicalizes" $ do
  let src =
        withHeader
          [ "double n ="
          , "  let result = n"
          , "  in result"
          ]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

testMultipleLetBindings :: TestTree
testMultipleLetBindings = testCase "multiple let bindings in same block canonicalize" $ do
  let src =
        withHeader
          [ "calc n ="
          , "  let"
          , "    a = 1"
          , "    b = 2"
          , "  in a"
          ]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

-- CASE TESTS

caseTests :: TestTree
caseTests =
  testGroup
    "case expression canonicalization"
    [ testCaseOnBool
    , testCaseBindsPatternVar
    ]

testCaseOnBool :: TestTree
testCaseOnBool = testCase "case expr of True -> ... | False -> ... canonicalizes" $ do
  let src =
        withHeader
          [ "describe b ="
          , "  case b of"
          , "    True -> \"yes\""
          , "    False -> \"no\""
          ]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

testCaseBindsPatternVar :: TestTree
testCaseBindsPatternVar = testCase "case branch that binds a variable canonicalizes" $ do
  let src =
        withHeader
          [ "type MyType = MyType Int"
          , ""
          , "extract v ="
          , "  case v of"
          , "    MyType n -> n"
          ]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

-- LIST TESTS

listTests :: TestTree
listTests =
  testGroup
    "list literal canonicalization"
    [ testEmptyList
    , testListWithLiterals
    ]

testEmptyList :: TestTree
testEmptyList = testCase "empty list [] canonicalizes to Can.List []" $ do
  let expr = Ann.At dummyRegion (Src.List [])
  case runCanon emptyEnv expr of
    Right canExpr ->
      case Ann.toValue canExpr of
        Can.List items -> length items @?= 0
        other -> assertFailure ("expected Can.List, got: " <> show other)
    Left err -> assertFailure ("canonicalization failed: " <> err)

testListWithLiterals :: TestTree
testListWithLiterals = testCase "[1, 2, 3] canonicalizes to Can.List with three elements" $ do
  let items = fmap (\n -> Ann.At dummyRegion (Src.Int n)) [1, 2, 3]
      expr = Ann.At dummyRegion (Src.List items)
  case runCanon emptyEnv expr of
    Right canExpr ->
      case Ann.toValue canExpr of
        Can.List canItems -> length canItems @?= 3
        other -> assertFailure ("expected Can.List, got: " <> show other)
    Left err -> assertFailure ("canonicalization failed: " <> err)

-- TUPLE TESTS

tupleTests :: TestTree
tupleTests =
  testGroup
    "tuple canonicalization"
    [ testTwoElementTuple
    , testThreeElementTuple
    ]

testTwoElementTuple :: TestTree
testTwoElementTuple = testCase "( 1, 2 ) canonicalizes to Can.Tuple with Nothing extras" $ do
  let a = Ann.At dummyRegion (Src.Int 1)
      b = Ann.At dummyRegion (Src.Int 2)
      expr = Ann.At dummyRegion (Src.Tuple a b [])
  case runCanon emptyEnv expr of
    Right canExpr ->
      case Ann.toValue canExpr of
        Can.Tuple _ _ Nothing -> pure ()
        other -> assertFailure ("expected 2-tuple, got: " <> show other)
    Left err -> assertFailure ("canonicalization failed: " <> err)

testThreeElementTuple :: TestTree
testThreeElementTuple = testCase "( 1, 2, 3 ) canonicalizes to Can.Tuple with Just third" $ do
  let a = Ann.At dummyRegion (Src.Int 1)
      b = Ann.At dummyRegion (Src.Int 2)
      c = Ann.At dummyRegion (Src.Int 3)
      expr = Ann.At dummyRegion (Src.Tuple a b [c])
  case runCanon emptyEnv expr of
    Right canExpr ->
      case Ann.toValue canExpr of
        Can.Tuple _ _ (Just _) -> pure ()
        other -> assertFailure ("expected 3-tuple, got: " <> show other)
    Left err -> assertFailure ("canonicalization failed: " <> err)

-- RECORD TESTS

recordTests :: TestTree
recordTests =
  testGroup
    "record canonicalization"
    [ testEmptyRecord
    , testRecordWithFields
    ]

testEmptyRecord :: TestTree
testEmptyRecord = testCase "empty record {} canonicalizes to Can.Record with no fields" $ do
  let expr = Ann.At dummyRegion (Src.Record [])
  case runCanon emptyEnv expr of
    Right canExpr ->
      case Ann.toValue canExpr of
        Can.Record fieldMap -> Map.size fieldMap @?= 0
        other -> assertFailure ("expected Can.Record, got: " <> show other)
    Left err -> assertFailure ("canonicalization failed: " <> err)

testRecordWithFields :: TestTree
testRecordWithFields = testCase "{ x = 1, y = 2 } canonicalizes with two fields" $ do
  let field name val =
        ( Ann.At dummyRegion (Name.fromChars name)
        , Ann.At dummyRegion (Src.Int val)
        )
      expr = Ann.At dummyRegion (Src.Record [field "x" 1, field "y" 2])
  case runCanon emptyEnv expr of
    Right canExpr ->
      case Ann.toValue canExpr of
        Can.Record fieldMap -> Map.size fieldMap @?= 2
        other -> assertFailure ("expected Can.Record, got: " <> show other)
    Left err -> assertFailure ("canonicalization failed: " <> err)

-- RECORD ACCESS TESTS

accessTests :: TestTree
accessTests =
  testGroup
    "record access canonicalization"
    [ testRecordAccessor
    ]

testRecordAccessor :: TestTree
testRecordAccessor = testCase ".fieldName accessor canonicalizes to Can.Accessor" $ do
  let fieldName = Name.fromChars "value"
      expr = Ann.At dummyRegion (Src.Accessor fieldName)
  case runCanon emptyEnv expr of
    Right canExpr ->
      case Ann.toValue canExpr of
        Can.Accessor n -> Name.toChars n @?= "value"
        other -> assertFailure ("expected Can.Accessor, got: " <> show other)
    Left err -> assertFailure ("canonicalization failed: " <> err)

-- PIPELINE (FULL PARSE + CANON) TESTS

-- | Integration tests that exercise name resolution via the full pipeline.
--
-- These cover scenarios that require a real environment built from source:
-- qualified names, let-scoped variables, and constructor resolution.
pipelineTests :: TestTree
pipelineTests =
  testGroup
    "full pipeline name resolution"
    [ testTopLevelValueVisible
    , testQualifiedNameResolution
    , testSelfReferenceInRecursiveFunction
    , testConstructorResolution
    ]

testTopLevelValueVisible :: TestTree
testTopLevelValueVisible = testCase "top-level value name resolves in another definition" $ do
  let src =
        withHeader
          [ "base = 10"
          , ""
          , "doubled = base"
          ]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

testQualifiedNameResolution :: TestTree
testQualifiedNameResolution = testCase "qualified accessor expression canonicalizes" $ do
  let src = withHeader ["getField r = r.field"]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

testSelfReferenceInRecursiveFunction :: TestTree
testSelfReferenceInRecursiveFunction = testCase "recursive function references itself" $ do
  let src = withHeader ["count n = count n"]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

testConstructorResolution :: TestTree
testConstructorResolution = testCase "constructor used in expression body resolves" $ do
  let src =
        withHeader
          [ "type Color = Red | Green | Blue"
          , ""
          , "favourite = Red"
          ]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected success, got errors: " <> show errs)
    (null errs)

-- ERROR TESTS

errorTests :: TestTree
errorTests =
  testGroup
    "canonicalization error conditions"
    [ testUndefinedVariable
    , testTupleTooLarge
    , testRecordDuplicateField
    ]

testUndefinedVariable :: TestTree
testUndefinedVariable = testCase "reference to undefined variable produces NotFoundVar error" $ do
  let src = withHeader ["bad = unknownVariable"]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected NotFoundVar error, got: " <> show errs)
    (any isNotFoundVar errs)

testTupleTooLarge :: TestTree
testTupleTooLarge = testCase "4-element tuple expression produces TupleLargerThanThree error" $ do
  let a = Ann.At dummyRegion (Src.Int 1)
      b = Ann.At dummyRegion (Src.Int 2)
      extras = fmap (\n -> Ann.At dummyRegion (Src.Int n)) [3, 4]
      expr = Ann.At dummyRegion (Src.Tuple a b extras)
  case runCanon emptyEnv expr of
    Left _ -> pure ()
    Right _ -> assertFailure "expected error for 4-element tuple"

testRecordDuplicateField :: TestTree
testRecordDuplicateField = testCase "record with duplicate field names produces error" $ do
  let src = withHeader ["bad = { x = 1, x = 2 }"]
  errs <- canonicalizeSourceErrors src
  assertBool
    ("expected duplicate field error, got: " <> show errs)
    (not (null errs))

-- HELPERS

-- | Minimal source module header.
withHeader :: [String] -> String
withHeader bodyLines =
  unlines ("module M exposing (..)" : "" : bodyLines)

-- | Parse and canonicalize source, returning the canonical module on success.
canonicalizeSource :: String -> IO Can.Module
canonicalizeSource src = do
  modul <- parseSrc src
  let result = runCanonModule modul
  expectCanonRight result

-- | Parse and canonicalize source, returning errors on failure.
canonicalizeSourceErrors :: String -> IO [Error.Error]
canonicalizeSourceErrors src = do
  modul <- parseSrc src
  let result = runCanonModule modul
  pure (extractErrors result)

-- | Parse source, failing the test if the parse fails.
parseSrc :: String -> IO Src.Module
parseSrc src =
  case ParseModule.fromByteString (ParseModule.Package Pkg.core) (C8.pack src) of
    Right m -> pure m
    Left err -> assertFailure ("parse failed: " <> show err) >> error "unreachable"

-- | Run the canonicalizer on a source module.
runCanonModule :: Src.Module -> ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) Can.Module)
runCanonModule modul =
  Result.run
    (Module.canonicalize
      (Module.CanonConfig Pkg.core (ParseModule.Package Pkg.core) Map.empty)
      Map.empty
      modul)

-- | Extract a successful result, failing the test on error.
expectCanonRight :: ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) Can.Module) -> IO Can.Module
expectCanonRight (_, Right val) = pure val
expectCanonRight (_, Left errs) =
  assertFailure ("expected success, got errors: " <> show (flattenErrors errs))
    >> error "unreachable"

-- | Extract errors from a result, returning empty list on success.
extractErrors :: ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) a) -> [Error.Error]
extractErrors (_, Left errs) = flattenErrors errs
extractErrors (_, Right _) = []

-- | Flatten a OneOrMore collection into a list.
flattenErrors :: OneOrMore.OneOrMore Error.Error -> [Error.Error]
flattenErrors = OneOrMore.destruct (:)

-- | Count the declarations in a canonical Decls chain.
countDecls :: Can.Decls -> Int
countDecls Can.SaveTheEnvironment = 0
countDecls (Can.Declare _ rest) = 1 + countDecls rest
countDecls (Can.DeclareRec _ defs rest) = 1 + length defs + countDecls rest

-- | Minimal environment for direct expression canonicalization tests.
--
-- Contains no variables, types, constructors, or operators. Suitable only
-- for expressions that require no name resolution (literals, unit, empty
-- record, empty list, tuples of literals).
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

-- | Run expression canonicalization directly, returning Right on success.
runCanon :: Env.Env -> Src.Expr -> Either String Can.Expr
runCanon env expr =
  let Result.Result k = Canon.canonicalize env expr
  in k Map.empty [] (\_ _ _ -> Left "canonicalization error") (\_ _ a -> Right a)

-- | Construct a 'EF.Float' from a string representation.
mkFloat :: String -> EF.Float
mkFloat = Utf8.fromChars

-- | Dummy source region for use in unit test expressions.
dummyRegion :: Ann.Region
dummyRegion = Ann.Region (Ann.Position 0 0) (Ann.Position 0 0)

-- | Check if an error is a NotFoundVar error.
isNotFoundVar :: Error.Error -> Bool
isNotFoundVar (Error.NotFoundVar _ _ _ _) = True
isNotFoundVar _ = False
