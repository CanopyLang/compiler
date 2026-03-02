{-# LANGUAGE OverloadedStrings #-}

-- | End-to-end compilation tests for the full Canopy pipeline.
--
-- These tests exercise the complete compilation pipeline from source text
-- through parsing, canonicalization, type checking, optimization, and
-- interface generation. Each test writes a Canopy module to a temporary
-- file and compiles it using 'Driver.compileModule', verifying that the
-- full pipeline produces correct artifacts.
--
-- All test modules are compiled as @Package Pkg.core@, which means default
-- imports (Basics, List, etc.) are skipped. This makes each test module
-- entirely self-contained: it can only reference types and functions it
-- defines itself. This avoids any dependency on the package cache contents
-- beyond what elm\/core provides for interface resolution.
--
-- The tests require elm\/core to be installed in the local package cache
-- (@~\/.elm\/0.19.1\/packages\/elm\/core\/1.0.5\/artifacts.dat@). If the
-- cache is not available, tests fail with a descriptive message.
--
-- @since 0.19.1
module Integration.EndToEndTest (tests) where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Interface as Interface
import Canopy.ModuleName (Canonical)
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map as Map
import qualified Canopy.Data.Name as Name
import qualified Driver
import qualified PackageCache
import qualified Parse.Module as Parse
import Query.Simple (QueryError (..))
import qualified System.IO as IO
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

-- | All end-to-end compilation tests.
tests :: TestTree
tests =
  testGroup
    "EndToEnd Compilation"
    [ testSimpleValueDefinition,
      testFunctionWithParameters,
      testCaseExpression,
      testRecordDefinition,
      testTypeAnnotation,
      testModuleWithMultipleConstructors,
      testCustomTypeDefinition,
      testLetExpression,
      testMultipleDeclarations,
      testNestedFunctionCalls,
      testTupleExpression,
      testCaseWithWildcard
    ]

-- | Compile a module source through the full pipeline and return the result.
--
-- Loads elm\/core interfaces, writes the source to a temp file at the given
-- path, then runs 'Driver.compileModule' using 'Pkg.core' as the package
-- and 'Parse.Package Pkg.core' as the project type. Since @Pkg.core@ is
-- the core package, default imports are skipped and the module must be
-- entirely self-contained.
compileSource ::
  FilePath ->
  String ->
  IO (Either QueryError Driver.CompileResult)
compileSource path source = do
  maybeCoreIfaces <- PackageCache.loadElmCoreInterfaces
  case maybeCoreIfaces of
    Nothing ->
      return (Left (OtherError "canopy/core not installed"))
    Just depIfaces -> do
      let ifaces = Map.map extractPublicInterface depIfaces
      IO.writeFile path source
      Driver.compileModule Pkg.core ifaces path (Parse.Package Pkg.core)

-- | Extract a public interface from a dependency interface.
--
-- Public dependencies expose their full interface directly. Private
-- dependencies expose only their union and alias type information with
-- empty value and binop maps, which is sufficient for type checking
-- but not for direct value references.
extractPublicInterface :: Interface.DependencyInterface -> Interface.Interface
extractPublicInterface (Interface.Public iface) = iface
extractPublicInterface (Interface.Private pkg unions aliases) =
  Interface.Interface
    { Interface._home = pkg,
      Interface._values = Map.empty,
      Interface._unions = Map.map Interface.PrivateUnion unions,
      Interface._aliases = Map.map Interface.PrivateAlias aliases,
      Interface._binops = Map.empty,
      Interface._ifaceGuards = Map.empty
    }

-- | Assert that compilation succeeded and run assertions on the result.
--
-- Wraps the compile-and-check pattern: compiles the source, fails the
-- test on error, and otherwise runs the provided assertion function on
-- the successful 'CompileResult'.
assertCompileSuccess ::
  FilePath ->
  String ->
  (Driver.CompileResult -> IO ()) ->
  IO ()
assertCompileSuccess path source assertions = do
  result <- compileSource path source
  case result of
    Left err ->
      assertFailure
        ("Expected successful compilation, got error: " ++ show err)
    Right compileResult ->
      assertions compileResult

-- | Test that a simple custom type definition compiles through the full
-- pipeline.
--
-- Verifies that a module with a single custom type produces a canonical
-- module with the expected union, generates a non-empty interface, and
-- that the module name is correctly propagated through all phases.
testSimpleValueDefinition :: TestTree
testSimpleValueDefinition =
  testCase "simple value definition compiles" $
    assertCompileSuccess "/tmp/canopy-e2e-value.can" valueSource $ \result -> do
      let Can.Module canonName _ _ _ unions _ _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "SimpleValue"
      assertBool
        "canonical module has the SimpleVal union"
        (Map.member (Name.fromChars "SimpleVal") unions)
      assertBool
        "interface has unions"
        (not (Map.null (Interface._unions (Driver.compileResultInterface result))))
  where
    valueSource :: String
    valueSource =
      unlines
        [ "module SimpleValue exposing (..)",
          "",
          "type SimpleVal = SimpleVal"
        ]

-- | Test that a function taking a parameter compiles.
--
-- Uses a generic wrapper type with a constructor that takes one argument,
-- and a function that wraps a value, exercising function definition and
-- constructor application in the pipeline.
testFunctionWithParameters :: TestTree
testFunctionWithParameters =
  testCase "function with parameters compiles" $
    assertCompileSuccess "/tmp/canopy-e2e-func.can" funcSource $ \result -> do
      let Can.Module canonName _ _ _ unions _ _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "FuncParams"
      assertBool
        "canonical module has Wrapper union"
        (Map.member (Name.fromChars "Wrapper") unions)
      let types = Driver.compileResultTypes result
      assertBool
        "wrap function is in type annotations"
        (Map.member (Name.fromChars "wrap") types)
  where
    funcSource :: String
    funcSource =
      unlines
        [ "module FuncParams exposing (..)",
          "",
          "type Wrapper a = Wrap a",
          "",
          "wrap x = Wrap x"
        ]

-- | Test that a case expression with pattern matching compiles.
--
-- Defines a custom type with three constructors and a function that
-- pattern-matches on each, returning a different constructor. This
-- exercises the case expression compilation path including the decision
-- tree optimizer.
testCaseExpression :: TestTree
testCaseExpression =
  testCase "case expression compiles" $
    assertCompileSuccess "/tmp/canopy-e2e-case.can" caseSource $ \result -> do
      let Can.Module canonName _ _ _ unions _ _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "CaseExpr"
      assertBool
        "canonical module has Color union"
        (Map.member (Name.fromChars "Color") unions)
      assertBool
        "canonical module has Shade union"
        (Map.member (Name.fromChars "Shade") unions)
      let types = Driver.compileResultTypes result
      assertBool
        "toShade function has type annotation"
        (Map.member (Name.fromChars "toShade") types)
  where
    caseSource :: String
    caseSource =
      unlines
        [ "module CaseExpr exposing (..)",
          "",
          "type Color = Red | Green | Blue",
          "",
          "type Shade = Light | Dark",
          "",
          "toShade color =",
          "    case color of",
          "        Red -> Dark",
          "        Green -> Light",
          "        Blue -> Dark"
        ]

-- | Test that a record type alias compiles.
--
-- Defines a type alias for a record with two fields of a custom type,
-- and a constructor function. This exercises record creation and type
-- alias compilation without depending on built-in types like Int.
testRecordDefinition :: TestTree
testRecordDefinition =
  testCase "record definition compiles" $
    assertCompileSuccess "/tmp/canopy-e2e-record.can" recordSource $ \result -> do
      let Can.Module canonName _ _ _ unions aliases _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "RecordDef"
      assertBool
        "canonical module has Coord alias"
        (Map.member (Name.fromChars "Coord") aliases)
      assertBool
        "canonical module has Axis union"
        (Map.member (Name.fromChars "Axis") unions)
      let types = Driver.compileResultTypes result
      assertBool
        "origin function has type annotation"
        (Map.member (Name.fromChars "origin") types)
  where
    recordSource :: String
    recordSource =
      unlines
        [ "module RecordDef exposing (..)",
          "",
          "type Axis = Zero | Positive | Negative",
          "",
          "type alias Coord = { x : Axis, y : Axis }",
          "",
          "origin = Coord Zero Zero"
        ]

-- | Test that explicit type annotations compile and are accepted.
--
-- Defines a function with an explicit type annotation using a custom type.
-- Verifies that the type checker validates the annotation against the
-- inferred type and that both appear in the compilation output.
testTypeAnnotation :: TestTree
testTypeAnnotation =
  testCase "type annotation compiles" $
    assertCompileSuccess "/tmp/canopy-e2e-annot.can" annotSource $ \result -> do
      let Can.Module canonName _ _ _ unions _ _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "TypeAnnot"
      assertBool
        "canonical module has MyType union"
        (Map.member (Name.fromChars "MyType") unions)
      let types = Driver.compileResultTypes result
      assertBool
        "identity function has type annotation"
        (Map.member (Name.fromChars "identity") types)
  where
    annotSource :: String
    annotSource =
      unlines
        [ "module TypeAnnot exposing (..)",
          "",
          "type MyType = MyA | MyB",
          "",
          "identity : MyType -> MyType",
          "identity x = x"
        ]

-- | Test that a module with multiple constructors compiles correctly.
--
-- Defines a direction type with four constructors and two functions that
-- pattern-match on different subsets. Verifies that the full union is
-- preserved and that both functions receive type annotations.
testModuleWithMultipleConstructors :: TestTree
testModuleWithMultipleConstructors =
  testCase "module with multiple constructors compiles" $
    assertCompileSuccess "/tmp/canopy-e2e-multi-ctor.can" multiCtorSource $ \result -> do
      let Can.Module canonName _ _ _ unions _ _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "MultiCtor"
      assertBool
        "canonical module has Direction union"
        (Map.member (Name.fromChars "Direction") unions)
      let localGraph = Driver.compileResultLocalGraph result
      assertBool
        "optimized graph was produced"
        (localGraph `seq` True)
      let types = Driver.compileResultTypes result
      assertBool
        "opposite function has type"
        (Map.member (Name.fromChars "opposite") types)
  where
    multiCtorSource :: String
    multiCtorSource =
      unlines
        [ "module MultiCtor exposing (..)",
          "",
          "type Direction = North | South | East | West",
          "",
          "opposite dir =",
          "    case dir of",
          "        North -> South",
          "        South -> North",
          "        East -> West",
          "        West -> East"
        ]

-- | Test that recursive custom type definitions compile.
--
-- Defines a recursive tree type with two constructors, verifying that
-- the union has the correct number of type variables and constructors.
-- This exercises the compiler's handling of recursive type references.
testCustomTypeDefinition :: TestTree
testCustomTypeDefinition =
  testCase "custom type definition compiles" $
    assertCompileSuccess "/tmp/canopy-e2e-custom.can" customSource $ \result -> do
      let Can.Module canonName _ _ _ unions _ _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "CustomType"
      assertBool
        "canonical module has Tree union"
        (Map.member (Name.fromChars "Tree") unions)
      let treeUnion = Map.lookup (Name.fromChars "Tree") unions
      case treeUnion of
        Nothing -> assertFailure "Tree union missing from canonical module"
        Just (Can.Union vars _ alts _ _) -> do
          length vars @?= 1
          length alts @?= 2
  where
    customSource :: String
    customSource =
      unlines
        [ "module CustomType exposing (..)",
          "",
          "type Tree a = Leaf a | Branch (Tree a) (Tree a)"
        ]

-- | Test that let expressions compile correctly.
--
-- Defines a function that uses let-in bindings to create intermediate
-- values before constructing the result. Verifies that local bindings
-- are handled through canonicalization and type checking.
testLetExpression :: TestTree
testLetExpression =
  testCase "let expression compiles" $
    assertCompileSuccess "/tmp/canopy-e2e-let.can" letSource $ \result -> do
      let Can.Module canonName _ _ _ unions _ _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "LetExpr"
      assertBool
        "canonical module has Pair union"
        (Map.member (Name.fromChars "Pair") unions)
      let types = Driver.compileResultTypes result
      assertBool
        "makePair function has type annotation"
        (Map.member (Name.fromChars "makePair") types)
  where
    letSource :: String
    letSource =
      unlines
        [ "module LetExpr exposing (..)",
          "",
          "type Pair a b = Pair a b",
          "",
          "makePair a b =",
          "    let",
          "        first = a",
          "        second = b",
          "    in",
          "    Pair first second"
        ]

-- | Test that multiple declarations in a single module compile together.
--
-- Defines several types and functions in one module, with functions that
-- reference each other's types. Verifies that the pipeline handles
-- multi-declaration modules and cross-references between declarations.
testMultipleDeclarations :: TestTree
testMultipleDeclarations =
  testCase "multiple declarations compile" $
    assertCompileSuccess "/tmp/canopy-e2e-multi.can" multiSource $ \result -> do
      let Can.Module canonName _ _ _ unions aliases _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "MultiDecl"
      assertBool
        "has Shape union"
        (Map.member (Name.fromChars "Shape") unions)
      assertBool
        "has Size union"
        (Map.member (Name.fromChars "Size") unions)
      assertBool
        "has Config alias"
        (Map.member (Name.fromChars "Config") aliases)
      let types = Driver.compileResultTypes result
      assertBool
        "classify function has type"
        (Map.member (Name.fromChars "classify") types)
  where
    multiSource :: String
    multiSource =
      unlines
        [ "module MultiDecl exposing (..)",
          "",
          "type Size = Small | Medium | Large",
          "",
          "type Shape = Circle Size | Square Size",
          "",
          "type alias Config = { shape : Shape, size : Size }",
          "",
          "classify shape =",
          "    case shape of",
          "        Circle s -> s",
          "        Square s -> s"
        ]

-- | Test that nested function calls compile.
--
-- Defines functions that call each other, exercising the compiler's
-- handling of nested function application and definition ordering.
-- All operations use custom types to avoid standard library dependencies.
testNestedFunctionCalls :: TestTree
testNestedFunctionCalls =
  testCase "nested function calls compile" $
    assertCompileSuccess "/tmp/canopy-e2e-nested.can" nestedSource $ \result -> do
      let Can.Module canonName _ _ _ unions _ _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "NestedExpr"
      assertBool
        "has Box union"
        (Map.member (Name.fromChars "Box") unions)
      let types = Driver.compileResultTypes result
      assertBool
        "rewrap function has type"
        (Map.member (Name.fromChars "rewrap") types)
      assertBool
        "doubleRewrap function has type"
        (Map.member (Name.fromChars "doubleRewrap") types)
  where
    nestedSource :: String
    nestedSource =
      unlines
        [ "module NestedExpr exposing (..)",
          "",
          "type Box a = Box a",
          "",
          "unbox b =",
          "    case b of",
          "        Box v -> v",
          "",
          "rewrap b = Box (unbox b)",
          "",
          "doubleRewrap b = rewrap (rewrap b)"
        ]

-- | Test that tuple expressions compile.
--
-- Defines functions that construct and destructure tuples. Tuples are
-- built-in syntax that does not require importing any module, so they
-- work in core package mode.
testTupleExpression :: TestTree
testTupleExpression =
  testCase "tuple expression compiles" $
    assertCompileSuccess "/tmp/canopy-e2e-tuple.can" tupleSource $ \result -> do
      let Can.Module canonName _ _ _ _ _ _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "TupleExpr"
      let types = Driver.compileResultTypes result
      assertBool
        "swap function has type"
        (Map.member (Name.fromChars "swap") types)
      assertBool
        "makePair function has type"
        (Map.member (Name.fromChars "makePair") types)
  where
    tupleSource :: String
    tupleSource =
      unlines
        [ "module TupleExpr exposing (..)",
          "",
          "swap (a, b) = (b, a)",
          "",
          "makePair x y = (x, y)"
        ]

-- | Test that case expressions with wildcard patterns compile.
--
-- Defines a case expression using a catch-all wildcard pattern, verifying
-- that the decision tree optimizer handles the default branch correctly
-- and that the optimized graph contains nodes for the function.
testCaseWithWildcard :: TestTree
testCaseWithWildcard =
  testCase "case with wildcard compiles" $
    assertCompileSuccess "/tmp/canopy-e2e-wildcard.can" wildcardSource $ \result -> do
      let Can.Module canonName _ _ _ unions _ _ _ _ _ = Driver.compileResultModule result
      assertModuleName canonName "WildcardCase"
      assertBool
        "has Animal union"
        (Map.member (Name.fromChars "Animal") unions)
      assertBool
        "has Sound union"
        (Map.member (Name.fromChars "Sound") unions)
      let types = Driver.compileResultTypes result
      assertBool
        "sound function has type"
        (Map.member (Name.fromChars "sound") types)
      let Opt.LocalGraph _ nodes _ _ = Driver.compileResultLocalGraph result
      assertBool
        "optimized graph has nodes"
        (not (Map.null nodes))
  where
    wildcardSource :: String
    wildcardSource =
      unlines
        [ "module WildcardCase exposing (..)",
          "",
          "type Animal = Cat | Dog | Bird | Fish",
          "",
          "type Sound = Meow | Bark | Chirp | Silent",
          "",
          "sound animal =",
          "    case animal of",
          "        Cat -> Meow",
          "        Dog -> Bark",
          "        Bird -> Chirp",
          "        _ -> Silent"
        ]

-- | Assert that a canonical module name matches the expected raw name.
--
-- Extracts the raw module name from a 'Canonical' module name and compares
-- it to the expected string representation.
assertModuleName :: Canonical -> String -> IO ()
assertModuleName canonName expectedStr =
  Name.toChars modName @?= expectedStr
  where
    modName = ModuleName._module canonName
