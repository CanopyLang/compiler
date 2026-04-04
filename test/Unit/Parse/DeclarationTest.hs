{-# LANGUAGE OverloadedStrings #-}

-- | Tests for Parse.Declaration — declaration parsing.
--
-- Validates that the parser correctly handles all top-level declaration forms:
--
--   * Value declarations with and without type annotations
--   * Custom type (union) declarations with constructors and type parameters
--   * Type alias declarations including record aliases
--   * Port declarations (Application project only)
--   * Infix operator declarations
--   * Deriving clauses on type and alias declarations
--   * Variance annotations on type parameters
--
-- Declarations are not individually exported from 'Parse.Declaration' so
-- all tests proceed through 'Parse.Module.fromByteString', which exercises
-- the full declaration parser.
--
-- @since 0.20.0
module Unit.Parse.DeclarationTest (tests) where

import qualified AST.Source as Src
import qualified AST.Utils.Binop as Binop
import qualified Canopy.Data.Name as Name
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Char8 as C8
import Data.Maybe (isNothing)
import qualified Parse.Module as ParseModule
import qualified Reporting.Annotation as Ann
import Test.Tasty
import Test.Tasty.HUnit

-- | Top-level test tree for Parse.Declaration.
tests :: TestTree
tests =
  testGroup
    "Parse.Declaration"
    [ valueDeclarationTests
    , typeDeclarationTests
    , typeAliasTests
    , portTests
    , infixTests
    , derivingTests
    , varianceTests
    , multipleDeclarationsTests
    ]

-- HELPERS

-- | Parse a source string as an Application module.
parseApp :: String -> Either String Src.Module
parseApp s =
  case ParseModule.fromByteString ParseModule.Application (C8.pack s) of
    Right m -> Right m
    Left err -> Left (show err)

-- | Parse a source string as a Package module.
parsePkg :: String -> Either String Src.Module
parsePkg s =
  case ParseModule.fromByteString (ParseModule.Package Pkg.core) (C8.pack s) of
    Right m -> Right m
    Left err -> Left (show err)

-- | Require a Right result, failing the test on Left.
requireRight :: (Show e) => Either e a -> IO a
requireRight (Right a) = pure a
requireRight (Left e) = assertFailure ("expected parse success, got: " <> show e) >> error "unreachable"

-- | Require a Left result, failing the test on Right.
requireLeft :: (Show a) => Either e a -> IO ()
requireLeft (Left _) = pure ()
requireLeft (Right a) = assertFailure ("expected parse failure, got: " <> show a)

-- | Wrap source lines in a minimal module header.
withHeader :: [String] -> String
withHeader bodyLines =
  unlines ("module M exposing (..)" : "" : bodyLines)

-- VALUE DECLARATION TESTS

valueDeclarationTests :: TestTree
valueDeclarationTests =
  testGroup
    "value declarations"
    [ testSimpleValue
    , testAnnotatedValue
    , testFunctionValue
    , testAnnotatedFunction
    , testMultiArgFunction
    ]

testSimpleValue :: TestTree
testSimpleValue = testCase "simple value binding parses" $ do
  m <- requireRight (parseApp (withHeader ["x = 42"]))
  length (Src._values m) @?= 1
  let Ann.At _ (Src.Value (Ann.At _ name) args _ tipe _) = head (Src._values m)
  Name.toChars name @?= "x"
  length args @?= 0
  assertBool "no type annotation expected" (isNothing tipe)

testAnnotatedValue :: TestTree
testAnnotatedValue = testCase "value with type annotation parses" $ do
  m <- requireRight (parseApp (withHeader ["x : Int", "x = 42"]))
  length (Src._values m) @?= 1
  let Ann.At _ (Src.Value (Ann.At _ name) _ _ tipe _) = head (Src._values m)
  Name.toChars name @?= "x"
  case tipe of
    Just _ -> pure ()
    Nothing -> assertFailure "expected type annotation"

testFunctionValue :: TestTree
testFunctionValue = testCase "function without annotation parses" $ do
  m <- requireRight (parseApp (withHeader ["double n = n"]))
  length (Src._values m) @?= 1
  let Ann.At _ (Src.Value (Ann.At _ name) args _ _ _) = head (Src._values m)
  Name.toChars name @?= "double"
  length args @?= 1

testAnnotatedFunction :: TestTree
testAnnotatedFunction = testCase "add : Int -> Int -> Int annotation and definition parse" $ do
  let src = withHeader ["add : Int -> Int -> Int", "add x y = x"]
  m <- requireRight (parseApp src)
  length (Src._values m) @?= 1
  let Ann.At _ (Src.Value (Ann.At _ name) args _ tipe _) = head (Src._values m)
  Name.toChars name @?= "add"
  length args @?= 2
  case tipe of
    Just _ -> pure ()
    Nothing -> assertFailure "expected type annotation"

testMultiArgFunction :: TestTree
testMultiArgFunction = testCase "function with three arguments parses all args" $ do
  m <- requireRight (parseApp (withHeader ["f a b c = a"]))
  let Ann.At _ (Src.Value _ args _ _ _) = head (Src._values m)
  length args @?= 3

-- TYPE DECLARATION TESTS

typeDeclarationTests :: TestTree
typeDeclarationTests =
  testGroup
    "custom type declarations"
    [ testSimpleEnum
    , testSingleConstructorUnit
    , testTypeWithPayload
    , testTypeWithParameter
    , testMultipleConstructors
    , testMaybeType
    ]

testSimpleEnum :: TestTree
testSimpleEnum = testCase "type Color = Red | Green | Blue parses three constructors" $ do
  m <- requireRight (parseApp (withHeader ["type Color = Red | Green | Blue"]))
  length (Src._unions m) @?= 1
  let Ann.At _ (Src.Union (Ann.At _ name) args _ ctors _) = head (Src._unions m)
  Name.toChars name @?= "Color"
  length args @?= 0
  length ctors @?= 3
  let ctorNames = fmap (\(Ann.At _ n, _) -> Name.toChars n) ctors
  ctorNames @?= ["Red", "Green", "Blue"]

testSingleConstructorUnit :: TestTree
testSingleConstructorUnit = testCase "type Unit = Unit parses single constructor" $ do
  m <- requireRight (parseApp (withHeader ["type Unit = Unit"]))
  let Ann.At _ (Src.Union (Ann.At _ name) _ _ ctors _) = head (Src._unions m)
  Name.toChars name @?= "Unit"
  length ctors @?= 1

testTypeWithPayload :: TestTree
testTypeWithPayload = testCase "type Shape = Circle Float | Rect Float Float parses payloads" $ do
  let src = withHeader ["type Shape = Circle Float | Rect Float Float"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Union _ _ _ ctors _) = head (Src._unions m)
  length ctors @?= 2
  let (_, circlePayloads) = head ctors
  let (_, rectPayloads) = ctors !! 1
  length circlePayloads @?= 1
  length rectPayloads @?= 2

testTypeWithParameter :: TestTree
testTypeWithParameter = testCase "type Box a = Box a parses type parameter" $ do
  m <- requireRight (parseApp (withHeader ["type Box a = Box a"]))
  let Ann.At _ (Src.Union _ args _ ctors _) = head (Src._unions m)
  length args @?= 1
  let Ann.At _ arg = head args
  Name.toChars arg @?= "a"
  let (_, payload) = head ctors
  length payload @?= 1

testMultipleConstructors :: TestTree
testMultipleConstructors = testCase "type Result err ok = Ok ok | Err err has two params" $ do
  let src = withHeader ["type Result err ok = Ok ok | Err err"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Union _ args _ ctors _) = head (Src._unions m)
  length args @?= 2
  length ctors @?= 2

testMaybeType :: TestTree
testMaybeType = testCase "type Maybe a = Just a | Nothing parses correctly" $ do
  m <- requireRight (parseApp (withHeader ["type Maybe a = Just a | Nothing"]))
  let Ann.At _ (Src.Union (Ann.At _ name) _ _ ctors _) = head (Src._unions m)
  Name.toChars name @?= "Maybe"
  length ctors @?= 2
  let ctorNames = fmap (\(Ann.At _ n, _) -> Name.toChars n) ctors
  ctorNames @?= ["Just", "Nothing"]

-- TYPE ALIAS TESTS

typeAliasTests :: TestTree
typeAliasTests =
  testGroup
    "type alias declarations"
    [ testSimpleAlias
    , testAliasWithParam
    , testRecordAlias
    , testTupleAlias
    , testAliasWithTwoParams
    ]

testSimpleAlias :: TestTree
testSimpleAlias = testCase "type alias Name = String parses" $ do
  m <- requireRight (parseApp (withHeader ["type alias Name = String"]))
  length (Src._aliases m) @?= 1
  let Ann.At _ (Src.Alias (Ann.At _ name) args _ _ _ _) = head (Src._aliases m)
  Name.toChars name @?= "Name"
  length args @?= 0

testAliasWithParam :: TestTree
testAliasWithParam = testCase "type alias Wrapper a = { value : a } parses param" $ do
  m <- requireRight (parseApp (withHeader ["type alias Wrapper a = { value : a }"]))
  let Ann.At _ (Src.Alias _ args _ _ _ _) = head (Src._aliases m)
  length args @?= 1
  let Ann.At _ argName = head args
  Name.toChars argName @?= "a"

testRecordAlias :: TestTree
testRecordAlias = testCase "type alias Point = { x : Float, y : Float } parses record" $ do
  let src = withHeader ["type alias Point = { x : Float, y : Float }"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Alias (Ann.At _ name) _ _ tipe _ _) = head (Src._aliases m)
  Name.toChars name @?= "Point"
  case Ann.toValue tipe of
    Src.TRecord fields Nothing -> length fields @?= 2
    _ -> assertFailure "expected TRecord with two fields"

testTupleAlias :: TestTree
testTupleAlias = testCase "type alias Pair = ( Int, Int ) parses tuple" $ do
  m <- requireRight (parseApp (withHeader ["type alias Pair = ( Int, Int )"]))
  let Ann.At _ (Src.Alias (Ann.At _ name) _ _ _ _ _) = head (Src._aliases m)
  Name.toChars name @?= "Pair"

testAliasWithTwoParams :: TestTree
testAliasWithTwoParams = testCase "type alias Dict k v = ... parses two params" $ do
  m <- requireRight (parseApp (withHeader ["type alias Pair k v = ( k, v )"]))
  let Ann.At _ (Src.Alias _ args _ _ _ _) = head (Src._aliases m)
  length args @?= 2

-- PORT TESTS

portTests :: TestTree
portTests =
  testGroup
    "port declarations"
    [ testPortApplication
    , testPortDisallowedInPackage
    , testMultiplePorts
    ]

testPortApplication :: TestTree
testPortApplication = testCase "port in port module under Application parses" $ do
  let src =
        unlines
          [ "port module Ports exposing (..)"
          , ""
          , "port log : String -> Cmd msg"
          ]
  m <- requireRight (parseApp src)
  case Src._effects m of
    Src.Ports ports -> do
      length ports @?= 1
      let Src.Port (Ann.At _ portName) _ = head ports
      Name.toChars portName @?= "log"
    _ -> assertFailure "expected Ports effects"

testPortDisallowedInPackage :: TestTree
testPortDisallowedInPackage = testCase "port in package project fails to parse" $ do
  let src = unlines ["module M exposing (..)", "", "port p : Int"]
  requireLeft (parsePkg src)

testMultiplePorts :: TestTree
testMultiplePorts = testCase "port module with two ports parses both" $ do
  let src =
        unlines
          [ "port module P exposing (..)"
          , ""
          , "port send : String -> Cmd msg"
          , ""
          , "port receive : (String -> msg) -> Sub msg"
          ]
  m <- requireRight (parseApp src)
  case Src._effects m of
    Src.Ports ports -> length ports @?= 2
    _ -> assertFailure "expected Ports effects"

-- INFIX TESTS

infixTests :: TestTree
infixTests =
  testGroup
    "infix declarations"
    [ testInfixLeft
    , testInfixRight
    , testInfixNon
    , testInfixPrecedence
    ]

testInfixLeft :: TestTree
testInfixLeft = testCase "infix left declaration parses left associativity" $ do
  let src = withHeader ["add x y = x", "infix left 6 (+) = add"]
  m <- requireRight (parseApp src)
  length (Src._binops m) @?= 1
  let Ann.At _ (Src.Infix op assoc _ _) = head (Src._binops m)
  Name.toChars op @?= "+"
  assoc @?= Binop.Left

testInfixRight :: TestTree
testInfixRight = testCase "infix right declaration parses right associativity" $ do
  let src = withHeader ["compose f g x = f (g x)", "infix right 9 (<<) = compose"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Infix op assoc _ _) = head (Src._binops m)
  Name.toChars op @?= "<<"
  assoc @?= Binop.Right

testInfixNon :: TestTree
testInfixNon = testCase "infix non declaration parses non-associativity" $ do
  let src = withHeader ["lt x y = x", "infix non 4 (<) = lt"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Infix _ assoc _ _) = head (Src._binops m)
  assoc @?= Binop.Non

testInfixPrecedence :: TestTree
testInfixPrecedence = testCase "infix declaration captures precedence level" $ do
  let src = withHeader ["mul x y = x", "infix left 7 (*) = mul"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Infix _ _ (Binop.Precedence prec) impl) = head (Src._binops m)
  prec @?= 7
  Name.toChars impl @?= "mul"

-- DERIVING TESTS

derivingTests :: TestTree
derivingTests =
  testGroup
    "deriving clauses"
    [ testDerivingOrdOnUnion
    , testDerivingEncodeOnAlias
    , testDerivingDecodeOnUnion
    , testDerivingMultiple
    ]

testDerivingOrdOnUnion :: TestTree
testDerivingOrdOnUnion = testCase "deriving (Ord) on union type parses" $ do
  let src = withHeader ["type Priority = Low | High", "  deriving (Ord)"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Union _ _ _ _ clauses) = head (Src._unions m)
  length clauses @?= 1
  case head clauses of
    Src.DeriveOrd -> pure ()
    _ -> assertFailure "expected DeriveOrd"

testDerivingEncodeOnAlias :: TestTree
testDerivingEncodeOnAlias = testCase "deriving (Encode) on type alias parses" $ do
  let src = withHeader ["type alias Name = String", "  deriving (Encode)"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Alias _ _ _ _ _ clauses) = head (Src._aliases m)
  length clauses @?= 1
  case head clauses of
    Src.DeriveEncode _ -> pure ()
    _ -> assertFailure "expected DeriveEncode"

testDerivingDecodeOnUnion :: TestTree
testDerivingDecodeOnUnion = testCase "deriving (Decode) on union type parses" $ do
  let src = withHeader ["type Color = Red | Blue", "  deriving (Decode)"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Union _ _ _ _ clauses) = head (Src._unions m)
  case head clauses of
    Src.DeriveDecode _ -> pure ()
    _ -> assertFailure "expected DeriveDecode"

testDerivingMultiple :: TestTree
testDerivingMultiple = testCase "deriving (Encode, Decode) parses both clauses" $ do
  let src = withHeader ["type Color = Red | Blue", "  deriving (Encode, Decode)"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Union _ _ _ _ clauses) = head (Src._unions m)
  length clauses @?= 2

-- VARIANCE TESTS

varianceTests :: TestTree
varianceTests =
  testGroup
    "variance annotations on type parameters"
    [ testCovariantParam
    , testContravariantParam
    , testInvariantParamDefault
    , testMixedVarianceParams
    ]

testCovariantParam :: TestTree
testCovariantParam = testCase "type ReadList (+a) = ReadList (List a) has covariant param" $ do
  let src = withHeader ["type ReadList (+a) = ReadList (List a)"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Union _ _ variances _ _) = head (Src._unions m)
  variances @?= [Src.Covariant]

testContravariantParam :: TestTree
testContravariantParam = testCase "type Sink (-a) = Sink (a -> Bool) has contravariant param" $ do
  let src = withHeader ["type Sink (-a) = Sink (a -> Bool)"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Union _ _ variances _ _) = head (Src._unions m)
  variances @?= [Src.Contravariant]

testInvariantParamDefault :: TestTree
testInvariantParamDefault = testCase "type Box a = Box a has invariant (default) param" $ do
  m <- requireRight (parseApp (withHeader ["type Box a = Box a"]))
  let Ann.At _ (Src.Union _ _ variances _ _) = head (Src._unions m)
  variances @?= [Src.Invariant]

testMixedVarianceParams :: TestTree
testMixedVarianceParams = testCase "type F (-a) (+b) = F (a -> b) has mixed variances" $ do
  let src = withHeader ["type F (-a) (+b) = F (a -> b)"]
  m <- requireRight (parseApp src)
  let Ann.At _ (Src.Union _ _ variances _ _) = head (Src._unions m)
  variances @?= [Src.Contravariant, Src.Covariant]

-- MULTIPLE DECLARATIONS TESTS

multipleDeclarationsTests :: TestTree
multipleDeclarationsTests =
  testGroup
    "multiple declarations in one module"
    [ testMixedDeclarations
    , testValuesAndTypes
    ]

testMixedDeclarations :: TestTree
testMixedDeclarations = testCase "module with value, union, alias, and infix all parse" $ do
  let src =
        unlines
          [ "module M exposing (..)"
          , ""
          , "type Color = Red | Green"
          , ""
          , "type alias Name = String"
          , ""
          , "greet n = n"
          , ""
          , "wrap x y = x"
          , "infix left 5 (<>) = wrap"
          ]
  m <- requireRight (parseApp src)
  length (Src._unions m) @?= 1
  length (Src._aliases m) @?= 1
  length (Src._values m) @?= 2
  length (Src._binops m) @?= 1

testValuesAndTypes :: TestTree
testValuesAndTypes = testCase "three value declarations count correctly" $ do
  let src =
        unlines
          [ "module M exposing (..)"
          , ""
          , "x = 1"
          , ""
          , "y = 2"
          , ""
          , "z = 3"
          ]
  m <- requireRight (parseApp src)
  length (Src._values m) @?= 3
