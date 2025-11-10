# Canopy Compiler Test Suite Improvement Plan
## Comprehensive Design Document for Test Suite Excellence

**Version:** 1.0
**Date:** 2025-10-28
**Status:** Design Phase
**Target:** Canopy Compiler Test Suite Modernization

---

## Executive Summary

This document provides a comprehensive architectural design for modernizing the Canopy compiler test suite to achieve world-class testing standards. The plan addresses systematic anti-patterns, test organization deficiencies, coverage gaps, and execution performance while maintaining strict adherence to CLAUDE.md standards.

### Current State Assessment

**Test Suite Metrics:**
- **107 test files** across Unit, Property, Integration, and Golden test categories
- **~13,309 lines** of test code
- **282 source files** to test across 5 packages
- **3 test categories** currently disabled (Property, Integration, Golden)

**Known Issues:**
- **37 Show instance anti-patterns** (testing framework mechanics)
- **113 lens getter/setter anti-patterns** (testing lens library mechanics)
- **8+ modules without tests** (Parser modules, utilities, JSON encoding)
- **Slow integration tests** causing CI bottlenecks
- **No test helper utilities** leading to duplication
- **No centralized test data management**
- **Sequential test execution** (no parallelization)

### Success Criteria

✅ **Zero anti-pattern violations** - All tests verify business logic, not framework mechanics
✅ **100% public function coverage** - Every exported function has meaningful tests
✅ **80%+ overall code coverage** - Meeting CLAUDE.md minimum threshold
✅ **50% faster test execution** - Through parallelization and optimization
✅ **Comprehensive test utilities** - Reusable helpers, generators, and fixtures
✅ **Clear test organization** - Intuitive structure matching source code
✅ **All test categories enabled** - Property, Integration, and Golden tests running

---

## Part 1: Test Suite Architecture Design

### 1.1 Proposed Directory Structure

```
canopy/test/
├── Main.hs                          # Test runner with parallel execution
├── TEST-SUITE-IMPROVEMENT-PLAN.md  # This document
├── Anti-Pattern-Analysis.md         # Current anti-pattern documentation
│
├── Helpers/                         # NEW: Centralized test utilities
│   ├── Assertions.hs               # Custom assertion helpers
│   ├── Generators.hs               # QuickCheck generators
│   ├── Fixtures.hs                 # Test data management
│   ├── Mocks.hs                    # Minimal mocking for IO
│   ├── Parallel.hs                 # Parallel test utilities
│   └── Matchers.hs                 # Custom matchers (e.g., AST equality)
│
├── Fixtures/                        # Test data and resources
│   ├── data/                       # Static test data
│   │   ├── packages/               # Sample package definitions
│   │   ├── modules/                # Sample Canopy modules
│   │   └── configs/                # Sample configurations
│   ├── golden/                     # Golden test baselines
│   │   ├── parser/                 # Parser golden outputs
│   │   ├── codegen/                # Code generation outputs
│   │   └── errors/                 # Error message outputs
│   └── temp/                       # Temporary test workspace (gitignored)
│
├── Unit/                           # Unit tests (fast, isolated)
│   ├── AST/                        # Abstract Syntax Tree tests
│   │   ├── SourceTest.hs
│   │   ├── CanonicalTest.hs
│   │   ├── OptimizedTest.hs      # REFACTORED: Remove Show anti-patterns
│   │   └── Utils/
│   │       ├── BinopTest.hs
│   │       ├── ShaderTest.hs
│   │       └── TypeTest.hs
│   ├── Parse/                      # Parser tests
│   │   ├── ExpressionTest.hs
│   │   ├── ModuleTest.hs
│   │   ├── TypeTest.hs
│   │   ├── PatternTest.hs
│   │   ├── NumberTest.hs          # NEW: Missing coverage
│   │   ├── StringTest.hs          # NEW: Missing coverage
│   │   ├── KeywordTest.hs         # NEW: Missing coverage
│   │   └── DeclarationTest.hs     # NEW: Missing coverage
│   ├── Builder/                    # Build system tests
│   ├── Canopy/                     # Core types tests
│   ├── CLI/                        # Command-line interface tests
│   ├── Data/                       # Data structure tests
│   ├── Develop/                    # Dev server tests
│   ├── Diff/                       # Diff utility tests
│   ├── File/                       # File system tests
│   ├── Init/                       # Init command tests
│   │   └── TypesTest.hs           # REFACTORED: Remove lens anti-patterns
│   ├── Install/                    # Install command tests
│   ├── Json/                       # JSON handling tests
│   │   ├── DecodeTest.hs
│   │   ├── EncodeTest.hs          # ENHANCED: Add missing tests
│   │   └── StringTest.hs
│   ├── Make/                       # Make command tests
│   ├── Query/                      # Query engine tests
│   ├── Terminal/                   # Terminal/REPL tests
│   ├── Watch/                      # File watching tests
│   └── Worker/                     # Worker pool tests
│
├── Property/                       # Property-based tests (QuickCheck)
│   ├── AST/
│   │   ├── CanonicalProps.hs
│   │   ├── OptimizedProps.hs
│   │   └── OptimizedBinaryProps.hs
│   ├── Data/
│   │   └── NameProps.hs
│   ├── Canopy/
│   │   └── VersionProps.hs
│   ├── Terminal/
│   │   └── ChompProps.hs
│   └── Commands/                   # Command property tests
│       ├── InitProps.hs
│       ├── InstallProps.hs
│       ├── MakeProps.hs
│       ├── DevelopProps.hs
│       └── WatchProps.hs
│
├── Integration/                    # Integration tests (slower, end-to-end)
│   ├── CompilerTest.hs            # Full compilation pipeline
│   ├── InitTest.hs                # REFACTORED: Remove lens anti-patterns
│   ├── InstallTest.hs             # Package installation
│   ├── MakeTest.hs                # Build command
│   ├── DevelopTest.hs             # Dev server
│   ├── WatchTest.hs               # File watching
│   ├── Terminal/
│   │   ├── TerminalIntegrationTest.hs
│   │   └── ChompIntegrationTest.hs
│   ├── JavaScript/
│   │   ├── RuntimeTest.hs
│   │   └── SyntaxTest.hs
│   ├── Builder/
│   │   └── PureBuilderIntegrationTest.hs
│   └── Formats/
│       ├── CanExtensionTest.hs
│       └── JsonIntegrationTest.hs
│
└── Golden/                         # Golden file tests (output verification)
    ├── sources/                    # Input source files
    │   ├── *.canopy
    │   └── *.can
    ├── expected/                   # Expected outputs
    │   └── *.golden
    └── tests/                      # Test definitions
        ├── ParseModuleGolden.hs
        ├── ParseExprGolden.hs
        ├── ParseTypeGolden.hs
        ├── ParseAliasGolden.hs
        ├── JsGenGolden.hs
        └── ElmCanopyGoldenTest.hs
```

### 1.2 Test Organization Principles

**1. Mirror Source Structure**
- Each source module has corresponding test module(s)
- Unit tests directly mirror the `packages/*/src/` structure
- Easy to locate tests for any source file

**2. Test Type Separation**
- **Unit**: Fast, isolated, test single functions/modules
- **Property**: Test invariants and laws with generated inputs
- **Integration**: Test cross-module interactions and workflows
- **Golden**: Test output correctness with baseline files

**3. Test Naming Conventions**
```haskell
-- Unit test module naming
module Unit.Parse.ExpressionTest where     -- Tests Parse.Expression
module Unit.AST.OptimizedTest where        -- Tests AST.Optimized

-- Test function naming
testParseSimpleNumber :: TestTree          -- Specific behavior
testParseRejectsInvalidNumber :: TestTree  -- Error condition
testParseNumberRoundtrip :: TestTree       -- Invariant

-- Test group naming
testGroup "Parse.Number Tests"             -- Module under test
  [ testGroup "decimal parsing"            -- Feature grouping
      [ testCase "simple integer" $ ...
      , testCase "fractional number" $ ...
      ]
  , testGroup "error handling"
      [ testCase "rejects empty string" $ ...
      ]
  ]
```

**4. Test Independence**
- Each test is self-contained
- No shared mutable state between tests
- Setup/teardown in individual tests or groups
- Parallel execution safe

---

## Part 2: Anti-Pattern Elimination Strategy

### 2.1 Show Instance Testing Anti-Pattern

**Problem:** Tests verify `show` output instead of business logic (37 occurrences)

**Example Anti-Pattern:**
```haskell
-- ❌ BAD: Testing Show instance, not business logic
testCase "Bool constructor representation" $ do
  let expr = Opt.Bool True
  show expr @?= "Bool True"
```

**Refactoring Strategy:**

1. **Identify Business Behavior:**
   - What is the actual purpose of the type?
   - What operations should it support?
   - What invariants must it maintain?

2. **Create Behavioral Tests:**
   ```haskell
   -- ✅ GOOD: Testing actual behavior
   testCase "Bool expression evaluates to truthy" $ do
     let expr = Opt.Bool True
     Opt.isTruthy expr @?= True

   testCase "Bool expression can be pattern matched" $ do
     let expr = Opt.Bool False
     case expr of
       Opt.Bool val -> val @?= False
       _ -> assertFailure "Expected Bool constructor"
   ```

3. **Create Extraction Helpers:**
   ```haskell
   -- Helper functions for testing AST without Eq instances
   module Helpers.Assertions where

   -- Extract boolean value from expression
   extractBoolValue :: Opt.Expr -> Maybe Bool
   extractBoolValue (Opt.Bool b) = Just b
   extractBoolValue _ = Nothing

   -- Check if expression is unit type
   isUnitExpression :: Opt.Expr -> Bool
   isUnitExpression Opt.Unit = True
   isUnitExpression _ = False

   -- Extract integer value
   extractIntValue :: Opt.Expr -> Maybe Int
   extractIntValue (Opt.Int i) = Just i
   extractIntValue _ = Nothing
   ```

**Files Requiring Refactoring:**
- `Unit/AST/OptimizedTest.hs` (35 violations) - **HIGH PRIORITY**
- `Unit/AST/Utils/ShaderTest.hs` (15 violations)
- `Unit/AST/Utils/BinopTest.hs` (4 violations)
- `Unit/Data/Utf8Test.hs` (2 violations)
- `Unit/File/Utf8Test.hs` (2 violations)

### 2.2 Lens Getter/Setter Testing Anti-Pattern

**Problem:** Tests verify lens mechanics instead of business logic (113 occurrences)

**Example Anti-Pattern:**
```haskell
-- ❌ BAD: Testing lens library mechanics
testCase "config verbose getter" $ do
  let config = defaultConfig
  config ^. configVerbose @?= False

-- ❌ BAD: Testing lens setter mechanics
testCase "config verbose setter" $ do
  let config = defaultConfig & configVerbose .~ True
  config ^. configVerbose @?= True
```

**Refactoring Strategy:**

1. **Distinguish Mechanical from Behavioral:**
   - **Mechanical**: `record ^. field @?= value` (testing lens)
   - **Behavioral**: Testing how field values affect behavior

2. **Replace with Behavioral Tests:**
   ```haskell
   -- ✅ GOOD: Testing business behavior
   testCase "verbose flag enables detailed logging" $ do
     let quietConfig = defaultConfig
         verboseConfig = defaultConfig & configVerbose .~ True
     getLogLevel quietConfig @?= LogQuiet
     getLogLevel verboseConfig @?= LogVerbose

   testCase "verbose flag affects compiler output" $ do
     let quietConfig = defaultConfig
         verboseConfig = defaultConfig & configVerbose .~ True
     length (getCompilerFlags quietConfig) <
       length (getCompilerFlags verboseConfig) @?
       "Verbose should add flags"
   ```

3. **Integration Test Approach:**
   ```haskell
   -- Test configuration flow through system
   testCase "configuration flows to compilation phase" $ do
     let config = defaultConfig & configOptLevel .~ O2
     result <- runCompiler config sampleModule
     case result of
       Right optimized ->
         hasOptimizations optimized @? "Should optimize at O2"
       Left err ->
         assertFailure ("Compilation failed: " <> show err)
   ```

**Decision Matrix:**
| Pattern | Keep or Transform? | Rationale |
|---------|-------------------|-----------|
| `record ^. field @?= value` alone | Transform | Tests lens mechanics |
| `businessFunc (record ^. field) @?= result` | Keep | Tests business logic using lens for access |
| `(record & field .~ val) ^. field @?= val` | Transform | Pure lens mechanics test |
| Integration test using lenses | Keep | Lenses are tool, testing behavior |

**Files Requiring Refactoring:**
- `Unit/Init/TypesTest.hs` (50+ violations) - **HIGHEST PRIORITY**
- `Unit/Develop/TypesTest.hs` (25+ violations)
- `Unit/DevelopMainTest.hs` (15+ violations)
- `Unit/DevelopTest.hs` (20+ violations)
- `Unit/InitTest.hs` (19+ violations)
- `Integration/InitTest.hs` (13+ violations)
- `Integration/DevelopTest.hs` (15+ violations)

### 2.3 Missing Test Coverage

**Problem:** 8+ modules have no dedicated test files

**Modules Without Tests:**
1. **Parse/Number.hs** - Number parsing logic
2. **Parse/String.hs** - String parsing and escaping
3. **Parse/Keyword.hs** - Reserved word handling
4. **Parse/Declaration.hs** - Declaration parsing
5. **Parse/Shader.hs** - Shader code parsing
6. **AST/Utils/Shader.hs** - Shader AST utilities
7. **AST/Utils/Binop.hs** - Binary operator utilities (partially tested)
8. **Json/Encode.hs** - JSON encoding (partially tested)

**Test Creation Strategy:**

```haskell
-- Example: Parse/Number.hs test suite
module Unit.Parse.NumberTest (tests) where

import qualified Parse.Number as Number
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "Parse.Number Tests"
  [ testGroup "integer parsing"
      [ testCase "simple positive integer" $
          Number.parse "42" @?= Right (Number.Integer 42)
      , testCase "negative integer" $
          Number.parse "-42" @?= Right (Number.Integer (-42))
      , testCase "zero" $
          Number.parse "0" @?= Right (Number.Integer 0)
      ]
  , testGroup "float parsing"
      [ testCase "simple decimal" $
          Number.parse "3.14" @?= Right (Number.Float 3.14)
      , testCase "scientific notation" $
          Number.parse "1e-10" @?= Right (Number.Float 1e-10)
      ]
  , testGroup "error handling"
      [ testCase "empty string" $
          case Number.parse "" of
            Left _ -> pure ()
            Right _ -> assertFailure "Should reject empty"
      , testCase "invalid format" $
          case Number.parse "12.34.56" of
            Left _ -> pure ()
            Right _ -> assertFailure "Should reject double decimal"
      ]
  , testGroup "edge cases"
      [ testCase "leading zeros" $
          Number.parse "007" @?= Right (Number.Integer 7)
      , testCase "very large number" $
          Number.parse "999999999999" >>= \n ->
            (n > Number.Integer 999999999998) @? "Should handle large nums"
      ]
  ]
```

---

## Part 3: Test Helper Utilities Design

### 3.1 Custom Assertions Module

**File:** `test/Helpers/Assertions.hs`

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | Custom assertion helpers for Canopy test suite.
--
-- Provides high-level assertions for common testing patterns,
-- reducing duplication and improving test readability.
module Helpers.Assertions
  ( -- * AST Assertions
    assertExprType,
    assertBoolExpr,
    assertIntExpr,
    assertStringExpr,
    assertListExpr,

    -- * Extraction Helpers
    extractBoolValue,
    extractIntValue,
    extractStringValue,
    extractListElements,
    isConstructor,

    -- * Compilation Assertions
    assertCompileSuccess,
    assertCompileError,
    assertErrorType,

    -- * File System Assertions
    assertFileExists,
    assertFileContains,
    assertDirectoryExists,

    -- * Result Assertions
    assertRight,
    assertLeft,
    assertJust,
    assertNothing,

    -- * Collection Assertions
    assertLength,
    assertContains,
    assertUnique,
    assertSorted,
  ) where

import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import Control.Monad (unless)
import qualified Data.List as List
import Data.Text (Text)
import qualified Data.Text as Text
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, (@?=))

-- | Assert an expression has a specific type
assertExprType :: String -> Opt.Expr -> Assertion
assertExprType expected expr = case expr of
  Opt.Bool _ -> expected @?= "Bool"
  Opt.Int _ -> expected @?= "Int"
  Opt.Str _ -> expected @?= "Str"
  Opt.Chr _ -> expected @?= "Chr"
  Opt.Float _ -> expected @?= "Float"
  _ -> assertFailure ("Unexpected expression type, expected: " <> expected)

-- | Extract boolean value from expression
extractBoolValue :: Opt.Expr -> Maybe Bool
extractBoolValue (Opt.Bool b) = Just b
extractBoolValue _ = Nothing

-- | Assert expression is boolean with specific value
assertBoolExpr :: Bool -> Opt.Expr -> Assertion
assertBoolExpr expected expr = case extractBoolValue expr of
  Just actual -> actual @?= expected
  Nothing -> assertFailure "Expression is not a boolean"

-- | Extract integer value from expression
extractIntValue :: Opt.Expr -> Maybe Int
extractIntValue (Opt.Int i) = Just i
extractIntValue _ = Nothing

-- | Assert expression is integer with specific value
assertIntExpr :: Int -> Opt.Expr -> Assertion
assertIntExpr expected expr = case extractIntValue expr of
  Just actual -> actual @?= expected
  Nothing -> assertFailure "Expression is not an integer"

-- | Check if expression is a specific constructor
isConstructor :: String -> Opt.Expr -> Bool
isConstructor "Bool" (Opt.Bool _) = True
isConstructor "Int" (Opt.Int _) = True
isConstructor "Str" (Opt.Str _) = True
isConstructor "Chr" (Opt.Chr _) = True
isConstructor "Float" (Opt.Float _) = True
isConstructor _ _ = False

-- | Assert compilation succeeds
assertCompileSuccess :: Either err a -> Assertion
assertCompileSuccess (Right _) = pure ()
assertCompileSuccess (Left _) = assertFailure "Compilation should succeed"

-- | Assert compilation fails
assertCompileError :: Either err a -> Assertion
assertCompileError (Left _) = pure ()
assertCompileError (Right _) = assertFailure "Compilation should fail"

-- | Assert Either is Right with specific value
assertRight :: (Eq a, Show a, Show e) => a -> Either e a -> Assertion
assertRight expected result = case result of
  Right actual -> actual @?= expected
  Left err -> assertFailure ("Expected Right, got Left: " <> show err)

-- | Assert Either is Left
assertLeft :: (Show a) => Either e a -> Assertion
assertLeft (Left _) = pure ()
assertLeft (Right val) = assertFailure ("Expected Left, got Right: " <> show val)

-- | Assert Maybe is Just with specific value
assertJust :: (Eq a, Show a) => a -> Maybe a -> Assertion
assertJust expected result = case result of
  Just actual -> actual @?= expected
  Nothing -> assertFailure "Expected Just, got Nothing"

-- | Assert Maybe is Nothing
assertNothing :: (Show a) => Maybe a -> Assertion
assertNothing Nothing = pure ()
assertNothing (Just val) = assertFailure ("Expected Nothing, got Just: " <> show val)

-- | Assert collection has specific length
assertLength :: (Show a) => Int -> [a] -> Assertion
assertLength expected list =
  length list @?= expected

-- | Assert list contains element
assertContains :: (Eq a, Show a) => a -> [a] -> Assertion
assertContains elem list =
  assertBool ("List should contain " <> show elem) (elem `elem` list)

-- | Assert all elements are unique
assertUnique :: (Eq a, Show a) => [a] -> Assertion
assertUnique list =
  let len = length list
      uniqueLen = length (List.nub list)
  in assertBool "List should have unique elements" (len == uniqueLen)

-- | Assert list is sorted
assertSorted :: (Ord a, Show a) => [a] -> Assertion
assertSorted list =
  assertBool "List should be sorted" (list == List.sort list)
```

### 3.2 QuickCheck Generators Module

**File:** `test/Helpers/Generators.hs`

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | QuickCheck generators for Canopy types.
--
-- Provides comprehensive property test generators following
-- CLAUDE.md guidelines for meaningful property testing.
module Helpers.Generators
  ( -- * Basic Generators
    genValidIdentifier,
    genModuleName,
    genPackageName,
    genVersion,

    -- * AST Generators
    genSourceExpr,
    genCanonicalExpr,
    genOptimizedExpr,
    genPattern,
    genType,

    -- * Complex Generators
    genModule,
    genOutline,
    genConstraint,

    -- * Generator Modifiers
    genSmall,
    genMedium,
    genLarge,
    genNested,
  ) where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Data.Char (isAlphaNum, isLower, isUpper)
import Data.Name (Name)
import qualified Data.Name as Name
import Data.Text (Text)
import qualified Data.Text as Text
import Test.QuickCheck

-- | Generate valid Canopy identifier (starts with lowercase)
genValidIdentifier :: Gen Text
genValidIdentifier = do
  first <- elements ['a'..'z']
  rest <- listOf (elements (['a'..'z'] <> ['A'..'Z'] <> ['0'..'9'] <> "_"))
  pure (Text.pack (first : rest))

-- | Generate valid module name (starts with uppercase)
genModuleName :: Gen ModuleName.ModuleName
genModuleName = do
  parts <- resize 3 (listOf1 genModulePart)
  pure (ModuleName.fromChars (Text.intercalate "." parts))
  where
    genModulePart = do
      first <- elements ['A'..'Z']
      rest <- listOf (elements (['a'..'z'] <> ['A'..'Z'] <> ['0'..'9']))
      pure (Text.pack (first : rest))

-- | Generate valid package name (author/project)
genPackageName :: Gen Pkg.Name
genPackageName = do
  author <- genValidIdentifier
  project <- genValidIdentifier
  pure (Pkg.Name author project)

-- | Generate semantic version
genVersion :: Gen V.Version
genVersion = V.Version
  <$> choose (0, 10)
  <*> choose (0, 20)
  <*> choose (0, 100)

-- | Generate source expression (small)
genSourceExpr :: Int -> Gen Src.Expr
genSourceExpr 0 = oneof
  [ genLiteralExpr
  , genVarExpr
  ]
genSourceExpr n = oneof
  [ genLiteralExpr
  , genVarExpr
  , genCallExpr (n `div` 2)
  , genIfExpr (n `div` 2)
  , genLetExpr (n `div` 2)
  ]

-- Helper for literal expressions
genLiteralExpr :: Gen Src.Expr
genLiteralExpr = oneof
  [ Src.Int <$> arbitrary
  , Src.Str <$> genValidIdentifier
  , Src.Chr <$> arbitrary
  , Src.Float <$> arbitrary
  ]

-- Helper for variable expressions
genVarExpr :: Gen Src.Expr
genVarExpr = Src.Var <$> (Name.fromChars <$> genValidIdentifier)

-- Helper for function call expressions
genCallExpr :: Int -> Gen Src.Expr
genCallExpr n = Src.Call
  <$> genSourceExpr (n `div` 2)
  <*> listOf1 (genSourceExpr (n `div` 2))

-- Helper for if expressions
genIfExpr :: Int -> Gen Src.Expr
genIfExpr n = Src.If
  <$> genSourceExpr (n `div` 2)
  <*> genSourceExpr (n `div` 2)
  <*> genSourceExpr (n `div` 2)

-- Helper for let expressions
genLetExpr :: Int -> Gen Src.Expr
genLetExpr n = Src.Let
  <$> listOf1 genDef
  <*> genSourceExpr (n `div` 2)
  where
    genDef = (,)
      <$> (Name.fromChars <$> genValidIdentifier)
      <*> genSourceExpr (n `div` 3)

-- | Generate pattern
genPattern :: Gen Src.Pattern
genPattern = oneof
  [ Src.PAnything <$> pure ()
  , Src.PVar <$> (Name.fromChars <$> genValidIdentifier)
  , Src.PLiteral <$> genLiteralPattern
  ]
  where
    genLiteralPattern = oneof
      [ Src.IntPattern <$> arbitrary
      , Src.StrPattern <$> genValidIdentifier
      , Src.ChrPattern <$> arbitrary
      ]

-- | Generate type annotation
genType :: Int -> Gen Src.Type
genType 0 = Src.TVar <$> (Name.fromChars <$> genValidIdentifier)
genType n = oneof
  [ Src.TVar <$> (Name.fromChars <$> genValidIdentifier)
  , Src.TLambda <$> genType (n `div` 2) <*> genType (n `div` 2)
  , Src.TRecord <$> listOf genField
  ]
  where
    genField = (,)
      <$> (Name.fromChars <$> genValidIdentifier)
      <*> genType (n `div` 3)

-- | Size modifiers
genSmall :: Gen a -> Gen a
genSmall = resize 5

genMedium :: Gen a -> Gen a
genMedium = resize 20

genLarge :: Gen a -> Gen a
genLarge = resize 50

genNested :: Int -> Gen a -> Gen a
genNested depth = resize depth
```

### 3.3 Test Fixtures Module

**File:** `test/Helpers/Fixtures.hs`

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | Test fixture management for Canopy tests.
--
-- Provides reusable test data, sample modules, and fixture
-- loading utilities to reduce duplication across tests.
module Helpers.Fixtures
  ( -- * Sample Modules
    sampleMainModule,
    sampleUtilsModule,
    sampleLibraryModule,

    -- * Sample Packages
    sampleCorePackage,
    sampleAppPackage,

    -- * Sample Configurations
    defaultTestConfig,
    verboseTestConfig,
    productionTestConfig,

    -- * Fixture Loading
    loadFixture,
    loadGoldenFile,
    withTempDirectory,
    withTempFile,

    -- * Sample Data
    sampleNames,
    sampleModuleNames,
    sampleVersions,
  ) where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Exception (bracket)
import qualified Data.ByteString as BS
import Data.Name (Name)
import qualified Data.Name as Name
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive)
import System.FilePath ((</>))
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory)

-- | Sample main module text
sampleMainModule :: Text
sampleMainModule = Text.unlines
  [ "module Main exposing (main)"
  , ""
  , "import Html exposing (text)"
  , ""
  , "main ="
  , "  text \"Hello, World!\""
  ]

-- | Sample utils module text
sampleUtilsModule :: Text
sampleUtilsModule = Text.unlines
  [ "module Utils exposing (identity, compose)"
  , ""
  , "identity : a -> a"
  , "identity x = x"
  , ""
  , "compose : (b -> c) -> (a -> b) -> (a -> c)"
  , "compose f g x = f (g x)"
  ]

-- | Sample library module with types
sampleLibraryModule :: Text
sampleLibraryModule = Text.unlines
  [ "module Library exposing (Person, makePerson)"
  , ""
  , "type alias Person ="
  , "  { name : String"
  , "  , age : Int"
  , "  }"
  , ""
  , "makePerson : String -> Int -> Person"
  , "makePerson name age ="
  , "  { name = name, age = age }"
  ]

-- | Sample core package (elm/core-like)
sampleCorePackage :: Pkg.Name
sampleCorePackage = Pkg.Name "elm" "core"

-- | Sample application package
sampleAppPackage :: Pkg.Name
sampleAppPackage = Pkg.Name "user" "my-app"

-- | Default test configuration
defaultTestConfig :: TestConfig
defaultTestConfig = TestConfig
  { testVerbose = False
  , testParallel = True
  , testTimeout = 5000
  }

-- | Verbose test configuration
verboseTestConfig :: TestConfig
verboseTestConfig = defaultTestConfig { testVerbose = True }

-- | Production-like test configuration
productionTestConfig :: TestConfig
productionTestConfig = TestConfig
  { testVerbose = False
  , testParallel = False
  , testTimeout = 30000
  }

-- | Test configuration type
data TestConfig = TestConfig
  { testVerbose :: Bool
  , testParallel :: Bool
  , testTimeout :: Int
  } deriving (Eq, Show)

-- | Load fixture file from fixtures directory
loadFixture :: FilePath -> IO Text
loadFixture path = Text.readFile ("test/fixtures" </> path)

-- | Load golden file from golden directory
loadGoldenFile :: FilePath -> IO BS.ByteString
loadGoldenFile path = BS.readFile ("test/Golden/expected" </> path)

-- | Execute action with temporary directory
withTempDirectory :: String -> (FilePath -> IO a) -> IO a
withTempDirectory template action = do
  tmpDir <- getCanonicalTemporaryDirectory
  bracket
    (createTempDirectory tmpDir template)
    removeDirectoryRecursive
    action

-- | Execute action with temporary file
withTempFile :: String -> Text -> (FilePath -> IO a) -> IO a
withTempFile name content action = withTempDirectory "canopy-test" $ \dir -> do
  let path = dir </> name
  Text.writeFile path content
  action path

-- | Sample identifier names
sampleNames :: [Name]
sampleNames =
  [ Name.fromChars "main"
  , Name.fromChars "identity"
  , Name.fromChars "compose"
  , Name.fromChars "map"
  , Name.fromChars "filter"
  ]

-- | Sample module names
sampleModuleNames :: [ModuleName.ModuleName]
sampleModuleNames =
  [ ModuleName.basics
  , ModuleName.maybe
  , ModuleName.fromChars "Utils"
  , ModuleName.fromChars "App.Main"
  , ModuleName.fromChars "Data.Model"
  ]

-- | Sample versions
sampleVersions :: [V.Version]
sampleVersions =
  [ V.one
  , V.Version 1 0 0
  , V.Version 1 2 3
  , V.Version 2 0 0
  ]
```

### 3.4 Parallel Test Utilities

**File:** `test/Helpers/Parallel.hs`

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | Parallel test execution utilities.
--
-- Provides helpers for safely parallelizing test execution
-- with proper resource management and isolation.
module Helpers.Parallel
  ( -- * Parallel Execution
    parallelTests,
    parallelTestGroup,

    -- * Resource Management
    withSharedResource,
    isolatedTest,

    -- * Performance
    timeTest,
    benchmarkTest,
  ) where

import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (bracket)
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase)

-- | Create test group that runs in parallel
parallelTestGroup :: String -> [TestTree] -> TestTree
parallelTestGroup name tests =
  testGroup name tests
  -- Note: Tasty provides parallel execution via --num-threads flag
  -- This is a placeholder for custom parallel logic if needed

-- | Time a test action
timeTest :: String -> IO a -> IO (a, Double)
timeTest name action = do
  start <- getCurrentTime
  result <- action
  end <- getCurrentTime
  let elapsed = realToFrac (diffUTCTime end start)
  pure (result, elapsed)

-- | Benchmark a test (for performance tests)
benchmarkTest :: String -> IO a -> TestTree
benchmarkTest name action = testCase name $ do
  (_, elapsed) <- timeTest name action
  putStrLn ("  [Time: " <> show elapsed <> "s]")
  pure ()
```

---

## Part 4: Golden Test Management

### 4.1 Golden Test Architecture

**Current Issues:**
- Golden files scattered across directories
- No clear update process
- Manual comparison logic
- Brittle exact string matching

**Proposed Architecture:**

```
test/Golden/
├── sources/           # Input files
│   ├── modules/       # Module parsing tests
│   │   ├── Simple.canopy
│   │   ├── WithTypes.canopy
│   │   └── Complex.can
│   ├── expressions/   # Expression parsing tests
│   │   ├── Literals.canopy
│   │   ├── Functions.canopy
│   │   └── Operators.can
│   └── types/         # Type parsing tests
│       ├── Basic.canopy
│       └── Advanced.canopy
│
├── expected/          # Expected outputs
│   ├── modules/
│   ├── expressions/
│   ├── types/
│   └── codegen/       # JS generation outputs
│
└── tests/            # Test definitions
    ├── ParseModuleGolden.hs
    ├── ParseExprGolden.hs
    ├── ParseTypeGolden.hs
    └── JsGenGolden.hs
```

### 4.2 Golden Test Helpers

**File:** `test/Helpers/Golden.hs`

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | Golden test utilities for Canopy test suite.
module Helpers.Golden
  ( -- * Golden Test Creation
    goldenTest,
    goldenVsText,
    goldenVsPretty,

    -- * File Management
    updateGoldenFiles,
    compareGoldenFile,

    -- * Output Normalization
    normalizeOutput,
    normalizeWhitespace,
    stripTimestamps,
  ) where

import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty (TestTree)

-- | Create golden test with automatic normalization
goldenTest :: String -> FilePath -> IO BL.ByteString -> TestTree
goldenTest name expected action =
  goldenVsString name expected (normalizeOutput <$> action)

-- | Normalize output for stable golden files
normalizeOutput :: BL.ByteString -> BL.ByteString
normalizeOutput =
  stripTimestamps . normalizeWhitespace

-- | Normalize whitespace (consistent line endings, trim)
normalizeWhitespace :: BL.ByteString -> BL.ByteString
normalizeWhitespace bs =
  BL.pack . Text.encodeUtf8 . Text.unlines . fmap Text.strip . Text.lines . Text.decodeUtf8 . BL.toStrict $ bs

-- | Strip timestamps from output (make tests deterministic)
stripTimestamps :: BL.ByteString -> BL.ByteString
stripTimestamps = id -- TODO: Implement regex-based stripping
```

### 4.3 Golden Test Update Process

**Makefile Targets:**

```makefile
# Update all golden files
update-golden:
	@echo "Updating golden test files..."
	@stack test --test-arguments "--accept"

# Update specific golden category
update-golden-parser:
	@stack test --test-arguments "--pattern=Golden.Parse --accept"

update-golden-codegen:
	@stack test --test-arguments "--pattern=Golden.JsGen --accept"
```

---

## Part 5: Integration Test Setup/Teardown

### 5.1 Integration Test Infrastructure

**Problem:** Current integration tests are:
- Slow (compile real packages)
- Not isolated (share state)
- Hard to debug (no clear setup/teardown)
- Disabled in CI (blocking other tests)

**Solution:** Structured integration test framework

### 5.2 Integration Test Base Module

**File:** `test/Helpers/Integration.hs`

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | Integration test infrastructure for Canopy.
--
-- Provides structured setup/teardown, resource management,
-- and test isolation for integration tests.
module Helpers.Integration
  ( -- * Test Environment
    IntegrationEnv(..),
    withIntegrationEnv,

    -- * Setup/Teardown
    setupTestProject,
    cleanupTestProject,

    -- * Package Management
    installTestPackage,
    createMockRegistry,

    -- * Compilation
    compileTestModule,
    buildTestProject,

    -- * Assertions
    assertCompiled,
    assertArtifactExists,
  ) where

import Control.Exception (bracket)
import qualified Data.Map as Map
import System.Directory
import System.FilePath
import qualified System.IO.Temp as Temp

-- | Integration test environment
data IntegrationEnv = IntegrationEnv
  { envTempDir :: FilePath
  , envProjectRoot :: FilePath
  , envCacheDir :: FilePath
  , envVerbose :: Bool
  } deriving (Eq, Show)

-- | Execute action with integration environment
withIntegrationEnv :: Bool -> (IntegrationEnv -> IO a) -> IO a
withIntegrationEnv verbose action =
  bracket setupEnv cleanupEnv action
  where
    setupEnv = do
      tmpDir <- Temp.getCanonicalTemporaryDirectory
      testDir <- Temp.createTempDirectory tmpDir "canopy-integration"
      let projectRoot = testDir </> "project"
          cacheDir = testDir </> "cache"
      createDirectoryIfMissing True projectRoot
      createDirectoryIfMissing True cacheDir
      pure $ IntegrationEnv testDir projectRoot cacheDir verbose

    cleanupEnv env =
      removeDirectoryRecursive (envTempDir env)

-- | Setup test project structure
setupTestProject :: IntegrationEnv -> IO ()
setupTestProject env = do
  let root = envProjectRoot env
  -- Create directory structure
  createDirectoryIfMissing True (root </> "src")
  createDirectoryIfMissing True (root </> "tests")

  -- Create canopy.json
  writeFile (root </> "canopy.json") $
    "{\n" <>
    "  \"type\": \"application\",\n" <>
    "  \"source-directories\": [\"src\"],\n" <>
    "  \"dependencies\": {\n" <>
    "    \"direct\": {},\n" <>
    "    \"indirect\": {}\n" <>
    "  }\n" <>
    "}"

-- | Cleanup test project
cleanupTestProject :: IntegrationEnv -> IO ()
cleanupTestProject env =
  removeDirectoryRecursive (envProjectRoot env)

-- | Compile test module in integration environment
compileTestModule :: IntegrationEnv -> FilePath -> IO (Either String FilePath)
compileTestModule env modulePath = do
  -- Implementation would call actual compiler
  -- For now, stub
  pure (Right (envProjectRoot env </> "build" </> "output.js"))

-- | Assert compilation succeeded
assertCompiled :: IntegrationEnv -> FilePath -> IO ()
assertCompiled env outputPath = do
  exists <- doesFileExist (envProjectRoot env </> outputPath)
  unless exists $
    fail ("Expected compiled output at: " <> outputPath)

-- | Assert artifact exists
assertArtifactExists :: IntegrationEnv -> FilePath -> IO ()
assertArtifactExists env artifactPath = do
  exists <- doesFileExist (envProjectRoot env </> artifactPath)
  unless exists $
    fail ("Expected artifact at: " <> artifactPath)
```

### 5.3 Integration Test Example

```haskell
-- Example integration test using new infrastructure
module Integration.CompileTest (tests) where

import qualified Helpers.Integration as IT
import Helpers.Fixtures (sampleMainModule)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "Compile Integration Tests"
  [ testCase "compile simple module" $
      IT.withIntegrationEnv False $ \env -> do
        -- Setup
        IT.setupTestProject env
        let modulePath = IT.envProjectRoot env </> "src/Main.canopy"
        writeFile modulePath (Text.unpack sampleMainModule)

        -- Execute
        result <- IT.compileTestModule env modulePath

        -- Assert
        case result of
          Right outputPath -> IT.assertCompiled env outputPath
          Left err -> assertFailure ("Compilation failed: " <> err)
  ]
```

---

## Part 6: Test Data Fixtures Design

### 6.1 Fixture Organization

**Structure:**

```
test/fixtures/
├── data/                      # Static test data
│   ├── packages/
│   │   ├── core-1.0.0.json   # Package metadata
│   │   ├── html-1.0.0.json
│   │   └── browser-1.0.0.json
│   ├── modules/
│   │   ├── Simple.canopy     # Simple module
│   │   ├── WithDeps.canopy   # Module with dependencies
│   │   └── Complex.can       # Complex module
│   ├── configs/
│   │   ├── app.json          # Application config
│   │   └── package.json      # Package config
│   └── types/
│       ├── Basic.elm         # Type test cases
│       └── Advanced.elm
│
├── golden/                    # Golden test baselines
│   └── (managed by Golden tests)
│
└── temp/                      # Temporary test workspace
    └── .gitignore            # Ignore all temp files
```

### 6.2 Fixture Loading API

**Enhanced Helpers/Fixtures.hs additions:**

```haskell
-- | Load package fixture
loadPackageFixture :: String -> IO PackageMetadata
loadPackageFixture name = do
  content <- loadFixture ("data/packages/" <> name <> ".json")
  case Json.decode content of
    Just pkg -> pure pkg
    Nothing -> fail ("Invalid package fixture: " <> name)

-- | Load module fixture
loadModuleFixture :: String -> IO Text
loadModuleFixture name =
  loadFixture ("data/modules/" <> name <> ".canopy")

-- | Load config fixture
loadConfigFixture :: String -> IO Outline
loadConfigFixture name = do
  content <- loadFixture ("data/configs/" <> name <> ".json")
  case Json.decode content of
    Just cfg -> pure cfg
    Nothing -> fail ("Invalid config fixture: " <> name)

-- | Create fixture in temp directory
createTempFixture :: String -> Text -> IO FilePath
createTempFixture name content = do
  tmpDir <- Temp.getCanonicalTemporaryDirectory
  testDir <- Temp.createTempDirectory tmpDir "canopy-fixture"
  let path = testDir </> name
  Text.writeFile path content
  pure path
```

---

## Part 7: Test Isolation Strategy

### 7.1 Isolation Principles

1. **No Shared Mutable State**
   - Each test creates its own data
   - No global variables
   - No shared file system state

2. **Temporary File Management**
   - All tests use temporary directories
   - Automatic cleanup via `bracket`
   - Unique names to avoid collisions

3. **Resource Cleanup**
   - Explicit setup/teardown
   - Exception-safe cleanup
   - No resource leaks

### 7.2 Test Isolation Patterns

**Pattern 1: Pure Unit Tests** (No IO, perfect isolation)
```haskell
testCase "version comparison" $ do
  let v1 = V.Version 1 0 0
      v2 = V.Version 2 0 0
  v1 < v2 @? "1.0.0 should be less than 2.0.0"
```

**Pattern 2: Isolated IO Tests** (Temporary resources)
```haskell
testCase "file compilation" $
  withTempDirectory "compile-test" $ \dir -> do
    let srcPath = dir </> "Main.canopy"
    writeFile srcPath sampleMainModule
    result <- compileFile srcPath
    assertCompileSuccess result
  -- Directory automatically cleaned up
```

**Pattern 3: Integration Tests** (Full environment)
```haskell
testCase "full compilation pipeline" $
  withIntegrationEnv False $ \env -> do
    setupTestProject env
    -- Test code
    -- Cleanup automatic
```

### 7.3 Test Ordering Independence

**Guidelines:**
- Tests can run in any order
- Tests don't depend on other tests
- No test numbering or sequencing
- Parallel execution safe

**Bad Example:**
```haskell
-- ❌ BAD: Test2 depends on Test1
test1 = testCase "setup" $ writeFile "shared.txt" "data"
test2 = testCase "use" $ readFile "shared.txt" >>= processData
```

**Good Example:**
```haskell
-- ✅ GOOD: Each test is independent
test1 = testCase "process data with setup" $ do
  writeFile "test1.txt" "data"
  processFile "test1.txt" >>= assertValid

test2 = testCase "process data different setup" $ do
  writeFile "test2.txt" "other data"
  processFile "test2.txt" >>= assertValid
```

---

## Part 8: Parallel Test Execution Strategy

### 8.1 Current Performance Issues

**Problems:**
- Sequential execution of 107 test files
- Integration tests compile real packages (very slow)
- No resource pooling
- Golden tests disabled (compilation cost)

**Goal:** 50% faster test execution

### 8.2 Parallelization Strategy

**Level 1: File-Level Parallelization** (Tasty built-in)
```haskell
-- Main.hs configuration
main :: IO ()
main = defaultMainWithIngredients ingredients tests
  where
    ingredients = defaultIngredients

-- Run with: stack test --test-arguments="+RTS -N4 -RTS"
-- Uses 4 cores for parallel test execution
```

**Level 2: Test Category Separation**
```haskell
-- Separate fast and slow tests
tests :: TestTree
tests = testGroup "All Tests"
  [ testGroup "Fast"
      [ unitTests         -- Run in parallel, ~1-2s total
      , propertyTests     -- Run in parallel, ~2-3s total
      ]
  , testGroup "Slow"
      [ integrationTests  -- Run in parallel, ~30s total
      , goldenTests       -- Run in parallel, ~10s total
      ]
  ]

-- CI can run:
-- make test-fast    # Unit + Property only
-- make test-all     # Everything
```

**Level 3: Resource Pooling**
```haskell
-- test/Helpers/Resources.hs
module Helpers.Resources where

import Control.Concurrent.STM
import qualified Data.Pool as Pool

-- | Shared compilation cache
data CompileCache = CompileCache
  { cacheModules :: TVar (Map ModuleName CompiledModule)
  , cachePool :: Pool.Pool CompilerState
  }

-- | Create resource pool for integration tests
createCompilePool :: IO CompileCache
createCompilePool = do
  modules <- newTVarIO Map.empty
  pool <- Pool.createPool
    initCompiler      -- Create resource
    cleanupCompiler   -- Destroy resource
    1                 -- Number of stripes
    60                -- Idle timeout (seconds)
    4                 -- Max resources per stripe
  pure $ CompileCache modules pool

-- | Use cached compilation
withCachedCompiler :: CompileCache -> (Compiler -> IO a) -> IO a
withCachedCompiler cache action =
  Pool.withResource (cachePool cache) action
```

### 8.3 Test Execution Configuration

**Makefile additions:**

```makefile
# Fast tests only (for development)
test-fast:
	@echo "Running fast tests (Unit + Property)..."
	@stack test --fast --test-arguments "+RTS -N4 -RTS --pattern=Unit|Property"

# All tests with optimal parallelization
test-all:
	@echo "Running all tests with parallelization..."
	@stack test --fast --test-arguments "+RTS -N4 -RTS"

# Integration tests only (for CI)
test-integration:
	@echo "Running integration tests..."
	@stack test --fast --test-arguments "+RTS -N2 -RTS --pattern=Integration"

# Benchmark test performance
test-benchmark:
	@echo "Benchmarking test suite..."
	@time stack test --fast --test-arguments "+RTS -N1 -RTS" 2>&1 | tee benchmark-n1.log
	@time stack test --fast --test-arguments "+RTS -N2 -RTS" 2>&1 | tee benchmark-n2.log
	@time stack test --fast --test-arguments "+RTS -N4 -RTS" 2>&1 | tee benchmark-n4.log
```

### 8.4 CI Configuration

**.github/workflows/test.yml**

```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  fast-tests:
    name: Fast Tests (Unit + Property)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: haskell/actions/setup@v2
        with:
          ghc-version: '9.8.4'
      - name: Cache dependencies
        uses: actions/cache@v2
        with:
          path: ~/.stack
          key: ${{ runner.os }}-stack-${{ hashFiles('stack.yaml') }}
      - name: Run fast tests
        run: make test-fast
        timeout-minutes: 5

  integration-tests:
    name: Integration Tests
    runs-on: ubuntu-latest
    needs: fast-tests
    steps:
      - uses: actions/checkout@v2
      - uses: haskell/actions/setup@v2
      - name: Cache dependencies
        uses: actions/cache@v2
        with:
          path: ~/.stack
          key: ${{ runner.os }}-stack-${{ hashFiles('stack.yaml') }}
      - name: Run integration tests
        run: make test-integration
        timeout-minutes: 10

  coverage:
    name: Test Coverage
    runs-on: ubuntu-latest
    needs: fast-tests
    steps:
      - uses: actions/checkout@v2
      - uses: haskell/actions/setup@v2
      - name: Run with coverage
        run: make test-coverage
      - name: Upload coverage
        uses: codecov/codecov-action@v2
```

---

## Part 9: Coverage Improvement Strategy

### 9.1 Current Coverage Gaps

**Modules Without Tests:**
1. Parse/Number.hs
2. Parse/String.hs
3. Parse/Keyword.hs
4. Parse/Declaration.hs
5. Parse/Shader.hs
6. AST/Utils/Shader.hs
7. AST/Utils/Binop.hs (partial)
8. Json/Encode.hs (partial)

**Target:** Add ~1000 lines of test code for 100% function coverage

### 9.2 Coverage Test Plan

**Phase 1: Parser Coverage** (3 new files, ~500 lines)

**File:** `test/Unit/Parse/NumberTest.hs`
```haskell
module Unit.Parse.NumberTest (tests) where

tests :: TestTree
tests = testGroup "Parse.Number Tests"
  [ testGroup "integer parsing"
      [ testCase "positive integer" $ ...
      , testCase "negative integer" $ ...
      , testCase "zero" $ ...
      , testCase "large integer" $ ...
      ]
  , testGroup "float parsing"
      [ testCase "simple decimal" $ ...
      , testCase "scientific notation" $ ...
      , testCase "negative float" $ ...
      ]
  , testGroup "hex parsing"
      [ testCase "valid hex" $ ...
      , testCase "hex with prefix" $ ...
      ]
  , testGroup "error cases"
      [ testCase "empty string" $ ...
      , testCase "invalid characters" $ ...
      , testCase "multiple decimals" $ ...
      ]
  ]
```

**File:** `test/Unit/Parse/StringTest.hs`
```haskell
module Unit.Parse.StringTest (tests) where

tests :: TestTree
tests = testGroup "Parse.String Tests"
  [ testGroup "basic strings"
      [ testCase "empty string" $ ...
      , testCase "simple string" $ ...
      , testCase "multiline string" $ ...
      ]
  , testGroup "escape sequences"
      [ testCase "newline escape" $ ...
      , testCase "tab escape" $ ...
      , testCase "quote escape" $ ...
      , testCase "unicode escape" $ ...
      ]
  , testGroup "string interpolation"
      [ testCase "simple interpolation" $ ...
      , testCase "nested interpolation" $ ...
      ]
  , testGroup "error cases"
      [ testCase "unclosed string" $ ...
      , testCase "invalid escape" $ ...
      ]
  ]
```

**File:** `test/Unit/Parse/KeywordTest.hs`
```haskell
module Unit.Parse.KeywordTest (tests) where

tests :: TestTree
tests = testGroup "Parse.Keyword Tests"
  [ testGroup "keyword recognition"
      [ testCase "if keyword" $ ...
      , testCase "then keyword" $ ...
      , testCase "else keyword" $ ...
      , testCase "let keyword" $ ...
      , testCase "in keyword" $ ...
      , testCase "case keyword" $ ...
      , testCase "of keyword" $ ...
      , testCase "type keyword" $ ...
      , testCase "alias keyword" $ ...
      ]
  , testGroup "not keywords"
      [ testCase "identifier starting with keyword" $ ...
      , testCase "keyword as part of identifier" $ ...
      ]
  ]
```

**Phase 2: AST Utilities Coverage** (2 enhanced files, ~300 lines)

Enhance existing partial tests:
- `AST/Utils/BinopTest.hs` - Add missing binary operators
- `AST/Utils/ShaderTest.hs` - Add shader AST manipulation tests

**Phase 3: JSON Encoding Coverage** (1 enhanced file, ~200 lines)

Add comprehensive encoding tests to `Json/EncodeTest.hs`

### 9.3 Coverage Measurement

**Tools:**
- HPC (Haskell Program Coverage)
- Stack built-in coverage reporting
- Codecov integration for CI

**Makefile targets:**

```makefile
# Generate coverage report
test-coverage:
	@echo "Running tests with coverage..."
	@stack test --coverage --fast
	@stack hpc report --all

# View coverage HTML report
coverage-report:
	@stack test --coverage --fast
	@stack hpc report --all --destdir=coverage-html
	@open coverage-html/hpc_index.html

# Check coverage threshold
coverage-check:
	@stack test --coverage --fast
	@stack hpc report --all | grep "expressions used" | \
		awk '{if ($$1+0 < 80.0) exit 1}' || \
		(echo "Coverage below 80% threshold" && exit 1)
```

### 9.4 Coverage Goals

| Category | Current | Target | Status |
|----------|---------|--------|--------|
| Unit Test Coverage | ~70% | 85% | 🟡 In Progress |
| Property Test Coverage | ~40% | 60% | 🔴 Needs Work |
| Integration Coverage | ~50% | 70% | 🟡 In Progress |
| Overall Coverage | ~60% | 80% | 🟡 In Progress |

**Priority:**
1. Parser modules (highest value, currently 0%)
2. AST utilities (medium value, currently 50%)
3. JSON encoding (low value, currently 70%)

---

## Part 10: Refactoring Strategy for Anti-Patterns

### 10.1 Phased Refactoring Approach

**Phase 1: Show Instance Anti-Patterns** (Week 1)
- **Target:** 37 violations across 8 files
- **Effort:** 8-12 hours
- **Priority:** HIGH

**Week 1 Schedule:**

**Day 1-2: AST.OptimizedTest.hs** (35 violations)
1. Create helper functions in `Helpers/Assertions.hs`
2. Replace all `show expr @?= "..."` with behavioral tests
3. Run tests after each change
4. Commit incrementally

**Day 3: Remaining Show tests** (2-4 violations each)
1. AST.Utils.ShaderTest.hs
2. AST.Utils.BinopTest.hs
3. Data.Utf8Test.hs
4. File.Utf8Test.hs

**Phase 2: Lens Anti-Patterns** (Week 2-3)
- **Target:** 113 violations across 10 files
- **Effort:** 20-30 hours
- **Priority:** MEDIUM

**Week 2 Schedule:**

**Day 1-2: Init.TypesTest.hs** (50+ violations)
1. Identify which tests are mechanical vs behavioral
2. Keep behavioral tests (using lenses as tools)
3. Transform mechanical tests to integration tests
4. Test validation of transformed tests

**Day 3-4: Develop tests** (40+ violations)
1. Develop.TypesTest.hs
2. DevelopMainTest.hs
3. DevelopTest.hs

**Week 3 Schedule:**

**Day 1-2: Init tests** (30+ violations)
1. InitTest.hs
2. Integration.InitTest.hs

**Day 3: Remaining lens tests** (20+ violations)
1. Integration.DevelopTest.hs
2. Other scattered violations

**Phase 3: Missing Coverage** (Week 4)
- **Target:** 8 modules without tests
- **Effort:** 15-20 hours
- **Priority:** MEDIUM

**Week 4 Schedule:**

**Day 1: Parser modules**
1. Parse.NumberTest.hs (new file)
2. Parse.StringTest.hs (new file)
3. Parse.KeywordTest.hs (new file)

**Day 2: More parser coverage**
1. Parse.DeclarationTest.hs (new file)
2. Parse.ShaderTest.hs (new file)

**Day 3: AST and JSON**
1. Enhance AST.Utils.BinopTest.hs
2. Enhance AST.Utils.ShaderTest.hs
3. Enhance Json.EncodeTest.hs

### 10.2 Refactoring Safety Checklist

For each file refactored:

- [ ] Read original tests and understand intent
- [ ] Create helper functions first (if needed)
- [ ] Transform one test at a time
- [ ] Run test suite after each transformation
- [ ] Verify test still catches real bugs (intentionally break code)
- [ ] Commit with clear message
- [ ] Code review before merging

### 10.3 Example Refactoring

**Before (Anti-pattern):**
```haskell
testCase "Global constructor" $ do
  let global = Opt.Global ModuleName.basics Name.true
  show global @?= "Global Basics True"
```

**Step 1: Understand Intent**
- What is this test really checking?
- It's verifying that Global constructor works
- It's checking module name and name storage

**Step 2: Create Behavioral Test**
```haskell
testCase "Global stores module name and identifier" $ do
  let global = Opt.Global ModuleName.basics Name.true
  case global of
    Opt.Global modName name -> do
      ModuleName.toChars modName @?= "Basics"
      Name.toChars name @?= "True"
```

**Step 3: Add Helper (if needed)**
```haskell
-- In Helpers/Assertions.hs
extractGlobalInfo :: Opt.Global -> (ModuleName, Name)
extractGlobalInfo (Opt.Global modName name) = (modName, name)

-- Test becomes:
testCase "Global stores module name and identifier" $ do
  let global = Opt.Global ModuleName.basics Name.true
      (modName, name) = extractGlobalInfo global
  ModuleName.toChars modName @?= "Basics"
  Name.toChars name @?= "True"
```

---

## Part 11: Step-by-Step Implementation Plan

### 11.1 Implementation Phases

**Phase 1: Infrastructure Setup** (Week 1)
- Create `test/Helpers/` directory structure
- Implement `Helpers/Assertions.hs`
- Implement `Helpers/Generators.hs`
- Implement `Helpers/Fixtures.hs`
- Implement `Helpers/Integration.hs`
- Implement `Helpers/Golden.hs`
- Update `Main.hs` for parallel execution
- **Deliverable:** Complete helper infrastructure

**Phase 2: Anti-Pattern Elimination** (Week 2-4)
- Week 2: Show instance anti-patterns (37 violations)
- Week 3-4: Lens anti-patterns (113 violations)
- **Deliverable:** Zero anti-pattern violations

**Phase 3: Missing Coverage** (Week 5)
- Add Parse.NumberTest.hs
- Add Parse.StringTest.hs
- Add Parse.KeywordTest.hs
- Add Parse.DeclarationTest.hs
- Enhance existing partial tests
- **Deliverable:** 100% function coverage

**Phase 4: Integration Test Optimization** (Week 6)
- Implement integration test infrastructure
- Refactor slow integration tests
- Add resource pooling
- Enable integration tests in CI
- **Deliverable:** Fast, reliable integration tests

**Phase 5: Golden Test Enhancement** (Week 7)
- Organize golden files
- Implement golden test helpers
- Add update process
- Enable golden tests in CI
- **Deliverable:** Complete golden test suite

**Phase 6: Parallel Execution** (Week 8)
- Configure parallel test execution
- Implement resource pooling
- Benchmark performance improvements
- Update CI configuration
- **Deliverable:** 50% faster test execution

### 11.2 Week-by-Week Schedule

**Week 1: Infrastructure**
- Day 1: Create Helpers directory, implement Assertions.hs
- Day 2: Implement Generators.hs, Fixtures.hs
- Day 3: Implement Integration.hs, Golden.hs
- Day 4: Update Main.hs, test infrastructure
- Day 5: Documentation, code review

**Week 2: Show Anti-Patterns**
- Day 1-2: Refactor AST.OptimizedTest.hs (35 violations)
- Day 3: Refactor AST.Utils tests (19 violations)
- Day 4: Refactor Data/File Utf8 tests (4 violations)
- Day 5: Verify all changes, integration test

**Week 3: Lens Anti-Patterns (Part 1)**
- Day 1-2: Refactor Init.TypesTest.hs (50 violations)
- Day 3-4: Refactor Develop.TypesTest.hs (25 violations)
- Day 5: Verify changes, integration test

**Week 4: Lens Anti-Patterns (Part 2)**
- Day 1-2: Refactor DevelopMainTest.hs, DevelopTest.hs (35 violations)
- Day 3: Refactor InitTest.hs (19 violations)
- Day 4: Refactor Integration tests (28 violations)
- Day 5: Verify all anti-patterns eliminated

**Week 5: Missing Coverage**
- Day 1: Parse.NumberTest.hs, Parse.StringTest.hs
- Day 2: Parse.KeywordTest.hs, Parse.DeclarationTest.hs
- Day 3: Enhance AST Utils tests
- Day 4: Enhance Json.EncodeTest.hs
- Day 5: Verify 80%+ coverage achieved

**Week 6: Integration Optimization**
- Day 1-2: Implement integration infrastructure
- Day 3: Refactor slow integration tests
- Day 4: Add resource pooling
- Day 5: Enable in CI, verify performance

**Week 7: Golden Tests**
- Day 1-2: Organize golden files
- Day 3: Implement golden helpers
- Day 4: Add update process
- Day 5: Enable in CI, verify golden tests

**Week 8: Parallel Execution**
- Day 1-2: Configure parallel execution
- Day 3: Implement resource pooling
- Day 4: Benchmark improvements
- Day 5: Final CI configuration, documentation

### 11.3 Success Metrics

**After Week 2:**
- ✅ Zero Show instance anti-patterns
- ✅ All AST tests use behavioral assertions
- ✅ Test infrastructure in place

**After Week 4:**
- ✅ Zero lens getter/setter anti-patterns
- ✅ All tests verify business logic
- ✅ ~150+ violations eliminated

**After Week 5:**
- ✅ 80%+ code coverage
- ✅ All public functions tested
- ✅ ~1000 new test lines added

**After Week 8:**
- ✅ 50% faster test execution
- ✅ All test categories enabled
- ✅ Complete test suite modernization

---

## Part 12: Code Examples for Key Improvements

### 12.1 Example: AST Testing Without Eq Instance

**Problem:** AST types lack Eq instances, making direct comparison impossible

**Solution: Property Extraction Pattern**

```haskell
-- Helpers/Assertions.hs additions

-- | Extract properties from Opt.Expr for testing
data ExprProperties = ExprProperties
  { exprType :: String
  , exprValue :: Maybe String
  , exprArity :: Maybe Int
  } deriving (Eq, Show)

-- | Extract testable properties from expression
extractExprProps :: Opt.Expr -> ExprProperties
extractExprProps expr = case expr of
  Opt.Bool b -> ExprProperties
    { exprType = "Bool"
    , exprValue = Just (show b)
    , exprArity = Nothing
    }
  Opt.Int i -> ExprProperties
    { exprType = "Int"
    , exprValue = Just (show i)
    , exprArity = Nothing
    }
  Opt.Str s -> ExprProperties
    { exprType = "Str"
    , exprValue = Just (Text.unpack s)
    , exprArity = Nothing
    }
  Opt.Call f args -> ExprProperties
    { exprType = "Call"
    , exprValue = Nothing
    , exprArity = Just (length args + 1)
    }
  _ -> ExprProperties
    { exprType = "Unknown"
    , exprValue = Nothing
    , exprArity = Nothing
    }

-- | Assert expression has expected properties
assertExprProps :: ExprProperties -> Opt.Expr -> Assertion
assertExprProps expected actual =
  extractExprProps actual @?= expected

-- Usage in tests:
testCase "Bool expression properties" $ do
  let expr = Opt.Bool True
      expected = ExprProperties "Bool" (Just "True") Nothing
  assertExprProps expected expr
```

### 12.2 Example: Behavioral Lens Testing

**Before (Mechanical):**
```haskell
testCase "config verbose getter" $ do
  let config = defaultConfig
  config ^. configVerbose @?= False
```

**After (Behavioral):**
```haskell
-- Add behavioral function to source code
getCompilerFlags :: InitConfig -> [String]
getCompilerFlags config =
  let base = ["-O2", "--no-debug"]
      verbose = if config ^. configVerbose
                then ["-v", "--trace"]
                else []
  in base <> verbose

-- Test the behavior
testCase "verbose flag adds compiler flags" $ do
  let quietConfig = defaultConfig
      verboseConfig = defaultConfig & configVerbose .~ True
  length (getCompilerFlags quietConfig) @?= 2
  length (getCompilerFlags verboseConfig) @?= 4
  assertContains "-v" (getCompilerFlags verboseConfig)
```

### 12.3 Example: Property Test with Custom Generator

```haskell
-- Property test using custom generators
testProperty "module name roundtrip" $
  forAll genModuleName $ \modName ->
    let text = ModuleName.toChars modName
        parsed = ModuleName.fromChars text
    in ModuleName.toChars parsed == text

-- Property test for invariants
testProperty "version ordering transitivity" $
  forAll genVersion $ \v1 ->
  forAll genVersion $ \v2 ->
  forAll genVersion $ \v3 ->
    (v1 < v2 && v2 < v3) ==> (v1 < v3)

-- Property test for laws
testProperty "lens get-set law" $
  forAll genConfig $ \config ->
  forAll arbitrary $ \verbose ->
    let updated = config & configVerbose .~ verbose
    in updated ^. configVerbose == verbose
```

### 12.4 Example: Integration Test with Setup/Teardown

```haskell
testCase "compile and run module" $
  withIntegrationEnv False $ \env -> do
    -- Setup
    setupTestProject env
    let modulePath = envProjectRoot env </> "src/Main.canopy"
    writeFile modulePath (Text.unpack sampleMainModule)

    -- Execute compilation
    compileResult <- compileTestModule env modulePath

    -- Assert compilation success
    case compileResult of
      Right outputPath -> do
        assertCompiled env outputPath
        output <- readFile (envProjectRoot env </> outputPath)
        assertContains "Hello, World!" output
      Left err -> assertFailure ("Compilation failed: " <> err)

    -- Teardown is automatic via bracket
```

### 12.5 Example: Golden Test with Normalization

```haskell
-- Golden test with automatic normalization
goldenModule :: String -> FilePath -> FilePath -> TestTree
goldenModule name srcPath goldenPath =
  goldenTest name goldenPath $ do
    src <- BS.readFile srcPath
    case M.fromByteString M.Application src of
      Left err ->
        pure (BL8.pack ("Parse error: " <> show err))
      Right modul ->
        pure (BL8.pack (normalizeModuleOutput modul))

-- Normalization ensures stable golden files
normalizeModuleOutput :: Src.Module -> String
normalizeModuleOutput modul =
  List.intercalate "\n" $
    filter (not . null) $
    fmap Text.strip $
    [ "Module: " <> Name.toChars (Src.getName modul)
    , "Exports: " <> normalizeExports (Src._exports modul)
    , "Values: " <> normalizeList (getValueNames modul)
    ]
  where
    normalizeList = List.intercalate ", " . List.sort
    normalizeExports = ... -- Normalize export format
```

### 12.6 Example: Parallel Resource Pooling

```haskell
-- Main.hs with resource pooling
main :: IO ()
main = do
  -- Create shared resources before tests
  compileCache <- createCompilePool

  -- Run tests with shared cache
  defaultMainWithIngredients ingredients $
    withResource (pure compileCache) (\_ -> pure ()) $ \cache ->
      tests cache

-- Tests use shared cache
integrationTests :: IO CompileCache -> TestTree
integrationTests cacheIO = testGroup "Integration Tests"
  [ testCase "compile module 1" $ do
      cache <- cacheIO
      result <- withCachedCompiler cache $ \compiler ->
        compileModule compiler "Module1"
      assertCompileSuccess result

  , testCase "compile module 2" $ do
      cache <- cacheIO
      result <- withCachedCompiler cache $ \compiler ->
        compileModule compiler "Module2"
      assertCompileSuccess result
  ]
  -- Both tests share the compiler cache
```

---

## Part 13: Risk Mitigation and Rollback Plan

### 13.1 Risks and Mitigation

**Risk 1: Breaking Existing Tests**
- **Mitigation:** Incremental refactoring, one file at a time
- **Rollback:** Git commit after each file transformation
- **Detection:** Run full test suite after each change

**Risk 2: Reduced Test Coverage During Refactoring**
- **Mitigation:** Keep old tests until new tests proven
- **Rollback:** Revert to previous commit
- **Detection:** Coverage reporting at each phase

**Risk 3: Performance Regression**
- **Mitigation:** Benchmark before/after each phase
- **Rollback:** Disable parallel execution if needed
- **Detection:** CI timing metrics

**Risk 4: Infrastructure Complexity**
- **Mitigation:** Start simple, add complexity gradually
- **Rollback:** Remove helper modules if too complex
- **Detection:** Code review feedback

**Risk 5: Time Overruns**
- **Mitigation:** Prioritize high-value changes first
- **Rollback:** Defer low-priority items
- **Detection:** Weekly progress reviews

### 13.2 Rollback Procedures

**File-Level Rollback:**
```bash
# Rollback single file
git checkout HEAD -- test/Unit/AST/OptimizedTest.hs

# Rollback entire phase
git revert <phase-commit-sha>
```

**Feature-Level Rollback:**
```bash
# Disable helper modules (if problematic)
mv test/Helpers test/Helpers.disabled

# Revert Main.hs changes
git checkout HEAD -- test/Main.hs
```

**CI Rollback:**
```yaml
# Disable problematic test category
jobs:
  test:
    steps:
      - name: Run tests
        run: make test-unit  # Only unit tests if integration fails
```

### 13.3 Validation Checkpoints

After each week, validate:
1. All tests pass
2. Coverage not decreased
3. No new anti-patterns introduced
4. Performance acceptable
5. Code review approved

**Validation Script:**
```bash
#!/bin/bash
# validate-checkpoint.sh

echo "=== Validation Checkpoint ==="

# 1. Run tests
echo "Running tests..."
if ! make test; then
  echo "❌ Tests failed!"
  exit 1
fi
echo "✅ All tests pass"

# 2. Check coverage
echo "Checking coverage..."
COVERAGE=$(make coverage-check 2>&1 | grep "expressions used" | awk '{print $1}')
if (( $(echo "$COVERAGE < 80" | bc -l) )); then
  echo "❌ Coverage below 80%: $COVERAGE%"
  exit 1
fi
echo "✅ Coverage at $COVERAGE%"

# 3. Check for anti-patterns
echo "Checking for anti-patterns..."
SHOW_PATTERNS=$(grep -r "show .* @?=" test/ | wc -l)
if [ $SHOW_PATTERNS -gt 0 ]; then
  echo "⚠️  Found $SHOW_PATTERNS show anti-patterns"
fi

# 4. Performance check
echo "Running performance benchmark..."
# TODO: Add timing

echo "=== Checkpoint Passed ==="
```

---

## Part 14: Continuous Improvement Process

### 14.1 Test Quality Metrics

**Track Over Time:**
- Test count (per category)
- Code coverage percentage
- Anti-pattern count
- Test execution time
- Test flakiness rate

**Dashboard (README badges):**
```markdown
![Tests](https://img.shields.io/badge/tests-500%2B-green)
![Coverage](https://img.shields.io/badge/coverage-85%25-brightgreen)
![Anti-patterns](https://img.shields.io/badge/anti--patterns-0-brightgreen)
![Speed](https://img.shields.io/badge/speed-2m30s-blue)
```

### 14.2 Regular Audits

**Monthly Test Audit:**
1. Review new tests for anti-patterns
2. Check coverage for new modules
3. Identify flaky tests
4. Review test performance
5. Update this plan based on findings

**Audit Checklist:**
```markdown
## Monthly Test Audit - [Month Year]

### Anti-Pattern Check
- [ ] No new show instance tests
- [ ] No new lens getter/setter tests
- [ ] All new tests have meaningful assertions

### Coverage Check
- [ ] Overall coverage >= 80%
- [ ] New modules have >= 80% coverage
- [ ] No functions without tests

### Performance Check
- [ ] Test suite runs in < 3 minutes
- [ ] No tests timeout
- [ ] Integration tests optimized

### Quality Check
- [ ] No flaky tests
- [ ] All tests independent
- [ ] Clear test names

### Actions
- [ ] Issue #XXX - Fix flaky test
- [ ] Issue #XXX - Add missing coverage
- [ ] Issue #XXX - Optimize slow test
```

### 14.3 Test Writing Guidelines

**For Future Test Authors:**

**DO:**
- ✅ Test behavior, not implementation
- ✅ Use helpers from `test/Helpers/`
- ✅ Write property tests for invariants
- ✅ Use fixtures for common data
- ✅ Make tests independent
- ✅ Use descriptive names
- ✅ Add tests before fixing bugs

**DON'T:**
- ❌ Test show output with `show x @?= "..."`
- ❌ Test lens mechanics with `record ^. field @?= value`
- ❌ Write reflexive tests (`x @?= x`)
- ❌ Use magic numbers without context
- ❌ Share state between tests
- ❌ Skip tests (fix or remove)
- ❌ Commit failing tests

### 14.4 Onboarding New Contributors

**Test Suite Onboarding Document:**

```markdown
# Canopy Test Suite - New Contributor Guide

## Welcome!

This guide will help you contribute tests to the Canopy compiler.

## Quick Start

1. **Run existing tests:**
   ```bash
   make test-fast  # Run unit and property tests
   ```

2. **Find where to add tests:**
   - Unit test for `packages/canopy-core/src/Parse/Number.hs`
   - Create `test/Unit/Parse/NumberTest.hs`

3. **Use test helpers:**
   ```haskell
   import Helpers.Assertions
   import Helpers.Generators
   import Helpers.Fixtures
   ```

4. **Follow patterns:**
   - Look at existing tests in same directory
   - See TEST-SUITE-IMPROVEMENT-PLAN.md for examples

## Common Patterns

### Unit Test
```haskell
testCase "descriptive name" $ do
  let input = ...
  result <- function input
  assertRight expected result
```

### Property Test
```haskell
testProperty "invariant name" $
  forAll genInput $ \input ->
    property (function input)
```

### Integration Test
```haskell
testCase "end-to-end workflow" $
  withIntegrationEnv False $ \env -> do
    setupTestProject env
    result <- workflow env
    assertSuccess result
```

## Resources

- CLAUDE.md - Coding standards
- TEST-SUITE-IMPROVEMENT-PLAN.md - This document
- test/Helpers/ - Helper modules
- #testing channel - Ask questions
```

---

## Part 15: Summary and Next Steps

### 15.1 Plan Summary

This comprehensive plan provides:

1. **Clear Architecture** - Well-organized test structure
2. **Anti-Pattern Elimination** - Systematic removal of 150+ violations
3. **Complete Coverage** - 80%+ coverage with missing tests added
4. **Performance Optimization** - 50% faster through parallelization
5. **Helper Infrastructure** - Reusable utilities and fixtures
6. **Quality Process** - Continuous improvement and audits

### 15.2 Expected Outcomes

**After Implementation:**

- ✅ **Zero anti-patterns** - All tests verify business logic
- ✅ **100% function coverage** - Every public function tested
- ✅ **80%+ overall coverage** - Exceeding CLAUDE.md minimum
- ✅ **50% faster execution** - Parallel execution optimized
- ✅ **Maintainable tests** - Clear structure and helpers
- ✅ **All categories enabled** - Property, Integration, Golden running
- ✅ **CI optimized** - Fast, reliable continuous integration
- ✅ **Developer friendly** - Easy to add new tests

### 15.3 Immediate Next Steps

**Week 1 Actions:**

1. **Review and approve this plan**
   - Team review session
   - Identify any concerns
   - Adjust timeline if needed

2. **Create Helpers infrastructure**
   - Create `test/Helpers/` directory
   - Implement `Assertions.hs` (core helpers)
   - Implement `Fixtures.hs` (test data)

3. **Start anti-pattern elimination**
   - Begin with `AST.OptimizedTest.hs`
   - Use new helpers
   - Verify improvements

4. **Set up tracking**
   - Create GitHub project board
   - Add issues for each phase
   - Track progress weekly

**Commands to Start:**

```bash
# 1. Create infrastructure
mkdir -p test/Helpers
touch test/Helpers/Assertions.hs
touch test/Helpers/Generators.hs
touch test/Helpers/Fixtures.hs
touch test/Helpers/Integration.hs
touch test/Helpers/Golden.hs

# 2. Run baseline tests
make test-coverage  # Record baseline

# 3. Start first refactoring
git checkout -b refactor/optimize-test
# Edit test/Unit/AST/OptimizedTest.hs
make test
git commit -m "refactor: eliminate Show anti-patterns in OptimizedTest"
```

### 15.4 Success Criteria Checklist

**Phase Completion Checklist:**

**Infrastructure (Week 1):**
- [ ] `test/Helpers/` directory created
- [ ] All helper modules implemented
- [ ] Helper tests added
- [ ] Documentation complete

**Anti-Patterns (Week 2-4):**
- [ ] Zero Show instance anti-patterns
- [ ] Zero lens getter/setter anti-patterns
- [ ] All tests use behavioral assertions
- [ ] Test suite still passes

**Coverage (Week 5):**
- [ ] Parse.NumberTest.hs added
- [ ] Parse.StringTest.hs added
- [ ] Parse.KeywordTest.hs added
- [ ] 80%+ coverage achieved

**Integration (Week 6):**
- [ ] Integration infrastructure implemented
- [ ] Slow tests optimized
- [ ] Resource pooling working
- [ ] Integration tests enabled

**Golden (Week 7):**
- [ ] Golden files organized
- [ ] Golden helpers implemented
- [ ] Update process documented
- [ ] Golden tests enabled

**Parallel (Week 8):**
- [ ] Parallel execution configured
- [ ] Performance benchmarked
- [ ] CI updated
- [ ] 50% faster execution

**Final Deliverables:**
- [ ] All test categories enabled
- [ ] Full test documentation
- [ ] CI green and fast
- [ ] Team trained on new patterns

---

## Appendix A: Quick Reference

### A.1 Common Test Patterns

**Unit Test:**
```haskell
testCase "function behavior" $ do
  let input = ...
  result <- function input
  result @?= expected
```

**Property Test:**
```haskell
testProperty "invariant" $
  forAll genInput $ \input ->
    property (function input)
```

**Integration Test:**
```haskell
testCase "workflow" $
  withIntegrationEnv False $ \env -> do
    result <- workflow env
    assertSuccess result
```

**Golden Test:**
```haskell
goldenTest "name" "expected.golden" $ do
  output <- generateOutput
  pure output
```

### A.2 Helper Functions Reference

**Assertions:**
- `assertExprType` - Check expression type
- `assertBoolExpr` - Check boolean expression
- `assertCompileSuccess` - Assert compilation succeeds
- `assertRight` - Assert Either is Right
- `assertLength` - Check collection length

**Generators:**
- `genValidIdentifier` - Generate identifier
- `genModuleName` - Generate module name
- `genVersion` - Generate version
- `genSourceExpr` - Generate AST expression

**Fixtures:**
- `sampleMainModule` - Sample main module
- `loadFixture` - Load fixture file
- `withTempDirectory` - Temporary directory

**Integration:**
- `withIntegrationEnv` - Integration environment
- `setupTestProject` - Create test project
- `compileTestModule` - Compile in environment

### A.3 Makefile Commands

```bash
make test              # Run all tests
make test-fast         # Unit + Property only
make test-unit         # Unit tests only
make test-property     # Property tests only
make test-integration  # Integration tests only
make test-coverage     # With coverage report
make test-watch        # Watch mode
make update-golden     # Update golden files
```

### A.4 Anti-Pattern Detection

**Check for anti-patterns:**
```bash
# Show instance tests
grep -r "show .* @?=" test/ | wc -l

# Lens getter tests
grep -r "\^\..*@?=" test/ | wc -l

# Reflexive equality
grep -r "@?=.*\1" test/
```

---

## Appendix B: File Checklist

### B.1 Files to Create

**Helpers:**
- [ ] `test/Helpers/Assertions.hs`
- [ ] `test/Helpers/Generators.hs`
- [ ] `test/Helpers/Fixtures.hs`
- [ ] `test/Helpers/Integration.hs`
- [ ] `test/Helpers/Golden.hs`
- [ ] `test/Helpers/Parallel.hs`

**New Tests:**
- [ ] `test/Unit/Parse/NumberTest.hs`
- [ ] `test/Unit/Parse/StringTest.hs`
- [ ] `test/Unit/Parse/KeywordTest.hs`
- [ ] `test/Unit/Parse/DeclarationTest.hs`

**Documentation:**
- [ ] This file: `TEST-SUITE-IMPROVEMENT-PLAN.md`
- [ ] `test/README.md` (test suite overview)
- [ ] `test/CONTRIBUTING.md` (test contribution guide)

### B.2 Files to Refactor

**High Priority (Week 2):**
- [ ] `test/Unit/AST/OptimizedTest.hs` (35 violations)

**Medium Priority (Week 3-4):**
- [ ] `test/Unit/Init/TypesTest.hs` (50 violations)
- [ ] `test/Unit/Develop/TypesTest.hs` (25 violations)
- [ ] `test/Unit/DevelopMainTest.hs` (15 violations)
- [ ] `test/Unit/DevelopTest.hs` (20 violations)
- [ ] `test/Unit/InitTest.hs` (19 violations)

**Lower Priority (Week 4):**
- [ ] `test/Integration/InitTest.hs` (13 violations)
- [ ] `test/Integration/DevelopTest.hs` (15 violations)
- [ ] Remaining scattered violations

### B.3 Files to Enhance

- [ ] `test/Unit/AST/Utils/BinopTest.hs` (add missing tests)
- [ ] `test/Unit/AST/Utils/ShaderTest.hs` (add missing tests)
- [ ] `test/Unit/Json/EncodeTest.hs` (add missing tests)

---

## Conclusion

This comprehensive test suite improvement plan provides a clear roadmap for modernizing the Canopy compiler test suite to world-class standards. By systematically eliminating anti-patterns, adding missing coverage, implementing helper infrastructure, and optimizing execution, we will achieve:

- **Higher Quality:** Tests verify business logic, not framework mechanics
- **Better Coverage:** 80%+ coverage with meaningful tests
- **Faster Execution:** 50% improvement through parallelization
- **Easier Maintenance:** Clear structure and reusable helpers
- **Confident Development:** Reliable test suite enables rapid iteration

The 8-week phased approach ensures safe, incremental improvements with clear validation checkpoints and rollback procedures. Each phase delivers tangible value while building toward the complete modernization goal.

**Let's build a test suite we can be proud of!**

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Status:** Ready for Review and Implementation
**Next Review:** After Phase 1 completion
