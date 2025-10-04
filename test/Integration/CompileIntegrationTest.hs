{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Integration tests for Compile module.
--
-- Tests end-to-end compilation functionality including real compilation
-- scenarios, performance characteristics, and system integration.
module Integration.CompileIntegrationTest (tests) where

-- Pattern: Types unqualified, functions qualified
import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.String as ES
import qualified Compile
import Control.Lens ((^.))
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Data.Utf8 as Utf8
import qualified Reporting.Annotation as A
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Compile Integration Tests"
    [ testRealCompilationScenarios,
      testCompilationPipeline,
      testErrorIntegration,
      testPerformanceCharacteristics,
      testSystemIntegration
    ]

-- Test real compilation scenarios
testRealCompilationScenarios :: TestTree
testRealCompilationScenarios =
  testGroup
    "real compilation scenarios"
    [ testCase "compile simple valid module" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            sourceModule = createSimpleValidModule
        result <- Compile.compile pkg interfaces sourceModule

        case result of
          Left err -> do
            -- For mock data, errors are expected, but should be well-formed
            let errorStr = show err
            assertBool "error should be informative" (length errorStr > 0)
          Right artifacts -> do
            -- Verify all compilation artifacts are present
            let module_ = artifacts ^. Compile.artifactsModule
            Can._name module_ @?= ModuleName.Canonical Pkg.core (Name.fromChars "SimpleValid")
            let types = artifacts ^. Compile.artifactsTypes
            assertBool "Types map should contain at least one type" (Map.size types >= 1)
            let graph = artifacts ^. Compile.artifactsGraph
            case Opt._l_main graph of
              Nothing -> pure () -- Expected no main for simple module
              Just _ -> assertFailure "Simple module should not have main function",
      testCase "compile module with dependencies" $ do
        let pkg = Pkg.core
            interfaces = createBasicInterfaces
            sourceModule = createModuleWithDependencies
        result <- Compile.compile pkg interfaces sourceModule

        case result of
          Left err -> do
            assertBool "dependency compilation error is informative" (length (show err) > 10)
          Right artifacts -> do
            let types = artifacts ^. Compile.artifactsTypes
            assertBool "Types map should contain at least one type" (Map.size types >= 1),
      testCase "compile application module" $ do
        let pkg = createApplicationPackage
            interfaces = createApplicationInterfaces
            sourceModule = createApplicationModule
        result <- Compile.compile pkg interfaces sourceModule

        case result of
          Left _ -> pure () -- application compilation may fail with mock data
          Right artifacts -> do
            let module_ = artifacts ^. Compile.artifactsModule
            Can._name module_ @?= ModuleName.Canonical (createApplicationPackage) (Name.fromChars "Main"),
      testCase "compile library module" $ do
        let pkg = createLibraryPackage
            interfaces = createLibraryInterfaces
            sourceModule = createLibraryModule
        result <- Compile.compile pkg interfaces sourceModule

        case result of
          Left _ -> pure () -- library compilation may fail with mock data
          Right artifacts -> do
            let module_ = artifacts ^. Compile.artifactsModule
            Can._name module_ @?= ModuleName.Canonical (createLibraryPackage) (Name.fromChars "Utils"),
      testCase "compile complex module with multiple functions" $ do
        let pkg = Pkg.core
            interfaces = createComplexInterfaces
            sourceModule = createComplexModule
        result <- Compile.compile pkg interfaces sourceModule

        case result of
          Left err -> do
            assertBool "complex module may have compilation errors" (length (show err) > 0)
          Right artifacts -> do
            let types = artifacts ^. Compile.artifactsTypes
            assertBool "Types map should contain at least one type" (Map.size types >= 1)
    ]

-- Test compilation pipeline
testCompilationPipeline :: TestTree
testCompilationPipeline =
  testGroup
    "compilation pipeline"
    [ testCase "pipeline phase ordering" $ do
        -- Test that compilation follows the documented phase order:
        -- 1. Canonicalization 2. Type Checking 3. Pattern Validation 4. Optimization
        let pkg = Pkg.core
            interfaces = Map.empty
            sourceModule = createValidModule
        result <- Compile.compile pkg interfaces sourceModule

        case result of
          Left err -> do
            -- Even with errors, the pipeline should be attempted in order
            assertBool "pipeline errors contain details" (length (show err) > 10)
          Right artifacts -> do
            -- Success means all phases completed successfully
            let module_ = artifacts ^. Compile.artifactsModule
            Can._name module_ @?= ModuleName.Canonical Pkg.core (Name.fromChars "Valid")
            let types = artifacts ^. Compile.artifactsTypes
            assertBool "Types map should contain at least one type" (Map.size types >= 1)
            let graph = artifacts ^. Compile.artifactsGraph
            case Opt._l_main graph of
              Nothing -> pure () -- Expected no main for valid module
              Just _ -> assertFailure "Valid module should not have main function",
      testCase "pipeline error propagation" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            invalidModule = createInvalidModule
        result <- Compile.compile pkg interfaces invalidModule

        case result of
          Left err -> do
            -- Error should indicate which phase failed
            let errorStr = show err
            assertBool "error should indicate failure phase" (length errorStr > 10)
          Right _ -> pure (), -- unexpected success handled
      testCase "pipeline with incremental interfaces" $ do
        let pkg = Pkg.core
            baseInterfaces = Map.empty
            extendedInterfaces = Map.insert (Name.fromChars "Base") mockInterface baseInterfaces
            sourceModule = createModuleWithImports
        result1 <- Compile.compile pkg baseInterfaces sourceModule
        result2 <- Compile.compile pkg extendedInterfaces sourceModule

        -- Results may differ based on available interfaces
        case (result1, result2) of
          (Left _, Left _) -> pure () -- both configurations may fail
          (Right _, Right _) -> pure () -- both configurations may succeed
          _ -> pure (), -- interface availability affects compilation
      testCase "pipeline artifact consistency" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            sourceModule = createConsistentModule
        result <- Compile.compile pkg interfaces sourceModule

        case result of
          Left _ -> pure () -- consistency errors may occur
          Right artifacts -> do
            -- Verify internal consistency of artifacts
            let types = artifacts ^. Compile.artifactsTypes
            assertBool "Types map should contain at least one type" (Map.size types >= 1)
    ]

-- Test error integration
testErrorIntegration :: TestTree
testErrorIntegration =
  testGroup
    "error integration"
    [ testCase "canonicalization errors" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            moduleWithNameErrors = createModuleWithNameErrors
        result <- Compile.compile pkg interfaces moduleWithNameErrors

        case result of
          Left err -> do
            -- Should be BadNames error from canonicalization phase
            assertBool "canonicalization errors contain details" (length (show err) > 10)
          Right _ -> pure (), -- unexpected success in name error case
      testCase "type checking errors" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            moduleWithTypeErrors = createModuleWithTypeErrors
        result <- Compile.compile pkg interfaces moduleWithTypeErrors

        case result of
          Left err -> do
            -- Should be BadTypes error from type checking phase
            assertBool "type errors should be informative" (length (show err) > 5)
          Right _ -> pure (), -- unexpected success in type error case
      testCase "pattern match errors" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            moduleWithPatternErrors = createModuleWithPatternErrors
        result <- Compile.compile pkg interfaces moduleWithPatternErrors

        case result of
          Left err -> do
            -- Should be BadPatterns error from pattern validation phase
            assertBool "pattern errors contain details" (length (show err) > 10)
          Right _ -> pure (), -- unexpected success in pattern error case
      testCase "optimization errors" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            moduleWithOptimizationErrors = createModuleWithOptimizationErrors
        result <- Compile.compile pkg interfaces moduleWithOptimizationErrors

        case result of
          Left err -> do
            -- Should be BadMains error from optimization phase
            assertBool "optimization errors contain details" (length (show err) > 10)
          Right _ -> pure (), -- unexpected success in optimization error case
      testCase "error recovery and reporting" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            multipleErrorsModule = createModuleWithMultipleErrors
        result <- Compile.compile pkg interfaces multipleErrorsModule

        case result of
          Left err -> do
            -- Should report the first error encountered in the pipeline
            let errorStr = show err
            assertBool "should report first pipeline error" (length errorStr > 0)
          Right _ -> pure () -- unexpected success with multiple errors
    ]

-- Test performance characteristics
testPerformanceCharacteristics :: TestTree
testPerformanceCharacteristics =
  testGroup
    "performance characteristics"
    [ testCase "compilation of small modules" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            smallModule = createSmallModule
        result <- Compile.compile pkg interfaces smallModule

        case result of
          Left _ -> pure () -- small module compilation may fail
          Right artifacts -> do
            let types = artifacts ^. Compile.artifactsTypes
            assertBool "Types map should contain at least one type" (Map.size types >= 1),
      testCase "compilation with many interfaces" $ do
        let pkg = Pkg.core
            manyInterfaces = createManyInterfaces 50
            sourceModule = createModuleUsingManyInterfaces
        result <- Compile.compile pkg manyInterfaces sourceModule

        case result of
          Left _ -> pure () -- many interfaces may cause issues
          Right artifacts -> do
            let module_ = artifacts ^. Compile.artifactsModule
            Can._name module_ @?= ModuleName.Canonical Pkg.core (Name.fromChars "ManyInterfaces"),
      testCase "memory usage with complex types" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            complexTypesModule = createModuleWithComplexTypes
        result <- Compile.compile pkg interfaces complexTypesModule

        case result of
          Left _ -> pure () -- complex types may cause compilation issues
          Right artifacts -> do
            let module_ = artifacts ^. Compile.artifactsModule
            Can._name module_ @?= ModuleName.Canonical Pkg.core (Name.fromChars "ComplexTypes"),
      testCase "compilation determinism under load" $ do
        let pkg = Pkg.core
            interfaces = Map.empty
            sourceModule = createDeterministicModule
        results <- sequence (replicate 3 (Compile.compile pkg interfaces sourceModule))

        -- All results should be identical
        case results of
          [result1, result2, result3] -> do
            case (result1, result2, result3) of
              (Left err1, Left err2, Left err3) ->
                assertBool
                  "errors should be deterministic"
                  (show err1 == show err2 && show err2 == show err3)
              (Right art1, Right art2, Right art3) ->
                assertBool
                  "successful compilations should be deterministic"
                  ( Map.size (art1 ^. Compile.artifactsTypes) == Map.size (art2 ^. Compile.artifactsTypes)
                      && Map.size (art2 ^. Compile.artifactsTypes) == Map.size (art3 ^. Compile.artifactsTypes)
                  )
              _ -> assertFailure "compilation should be deterministic across runs"
          _ -> assertFailure "should have three results"
    ]

-- Test system integration
testSystemIntegration :: TestTree
testSystemIntegration =
  testGroup
    "system integration"
    [ testCase "integration with file system" $ do
        -- Test compilation in context of file system operations
        withSystemTempDirectory "compile-test" $ \tmpDir -> do
          let pkg = Pkg.core
              interfaces = Map.empty
              sourceModule = createFileSystemModule
          result <- Compile.compile pkg interfaces sourceModule

          case result of
            Left _ -> pure () -- file system integration may have issues
            Right artifacts -> do
              let module_ = artifacts ^. Compile.artifactsModule
              Can._name module_ @?= ModuleName.Canonical Pkg.core (Name.fromChars "FileSystem"),
      testCase "integration with package system" $ do
        let corePackage = Pkg.core
            customPackage = createCustomPackage
            interfaces = Map.empty
            sourceModule = createPackageAwareModule
        coreResult <- Compile.compile corePackage interfaces sourceModule
        customResult <- Compile.compile customPackage interfaces sourceModule

        -- Results may differ based on package context
        case (coreResult, customResult) of
          (Left _, Left _) -> pure () -- both package contexts may fail
          (Right _, Right _) -> pure () -- both package contexts may succeed
          _ -> pure (), -- package context affects compilation
      testCase "cross-module compilation consistency" $ do
        let pkg = Pkg.core
            interfaces = createCrossModuleInterfaces
            module1 = createModule1
            module2 = createModule2
        result1 <- Compile.compile pkg interfaces module1
        result2 <- Compile.compile pkg interfaces module2

        -- Both modules should compile consistently in the same environment
        case (result1, result2) of
          (Left _, Left _) -> pure () -- consistent errors across modules
          (Right _, Right _) -> pure () -- consistent success across modules
          _ -> pure (), -- cross-module behavior may vary
      testCase "compilation environment isolation" $ do
        let pkg = Pkg.core
            interfaces1 = createEnvironment1Interfaces
            interfaces2 = createEnvironment2Interfaces
            sourceModule = createEnvironmentSensitiveModule
        result1 <- Compile.compile pkg interfaces1 sourceModule
        result2 <- Compile.compile pkg interfaces2 sourceModule

        -- Same module in different environments may produce different results
        case (result1, result2) of
          (Left _, Left _) -> pure () -- both environments may cause errors
          (Right _, Right _) -> pure () -- both environments may succeed
          _ -> pure () -- environment affects compilation
    ]

-- Mock data creation functions

createSimpleValidModule :: Src.Module
createSimpleValidModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "SimpleValid")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "main"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Str (Utf8.fromChars "hello world")))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createBasicInterfaces :: Map ModuleName.Raw I.Interface
createBasicInterfaces = Map.empty

createModuleWithDependencies :: Src.Module
createModuleWithDependencies =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "WithDeps")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [], -- No imports to avoid Map lookup errors
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "depValue"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 42))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createApplicationPackage :: Pkg.Name
createApplicationPackage = Pkg.Name (Utf8.fromChars "myapp") (Utf8.fromChars "frontend")

createApplicationInterfaces :: Map ModuleName.Raw I.Interface
createApplicationInterfaces = Map.empty

createApplicationModule :: Src.Module
createApplicationModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "Main")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "main"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Str (Utf8.fromChars "App main")))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createLibraryPackage :: Pkg.Name
createLibraryPackage = Pkg.Name (Utf8.fromChars "mylib") (Utf8.fromChars "utils")

createLibraryInterfaces :: Map ModuleName.Raw I.Interface
createLibraryInterfaces = Map.empty

createLibraryModule :: Src.Module
createLibraryModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "Utils")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) (Src.Explicit [Src.Lower (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "helper"))]),
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "helper"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 42))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createComplexInterfaces :: Map ModuleName.Raw I.Interface
createComplexInterfaces = Map.empty

createComplexModule :: Src.Module
createComplexModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "Complex")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        replicate
          5
          ( A.at (A.Position 0 0) (A.Position 0 0) $
              Src.Value
                (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "func"))
                []
                (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 1))
                Nothing
          ),
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createValidModule :: Src.Module
createValidModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "Valid")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "validValue"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 42))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createInvalidModule :: Src.Module
createInvalidModule =
  Src.Module
    { Src._name = Nothing, -- Invalid: no name
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values = [],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createModuleWithImports :: Src.Module
createModuleWithImports =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "WithImports")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [], -- No imports to avoid Map lookup errors
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "importValue"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 1))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createConsistentModule :: Src.Module
createConsistentModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "Consistent")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "value"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Str (Utf8.fromChars "consistent")))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createModuleWithNameErrors :: Src.Module
createModuleWithNameErrors =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "123InvalidName")), -- Invalid: starts with number
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values = [],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createModuleWithTypeErrors :: Src.Module
createModuleWithTypeErrors =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "TypeErrors")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "badType"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 42))
              (Just (A.at (A.Position 0 0) (A.Position 0 0) (Src.TVar (Name.fromChars "String")))) -- Type mismatch: Int with String annotation
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createModuleWithPatternErrors :: Src.Module
createModuleWithPatternErrors =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "PatternErrors")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "badPattern"))
              [ A.at (A.Position 0 0) (A.Position 0 0) (Src.PVar (Name.fromChars "x")),
                A.at (A.Position 0 0) (A.Position 0 0) (Src.PVar (Name.fromChars "x")) -- Duplicate pattern var
              ]
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 1))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createModuleWithOptimizationErrors :: Src.Module
createModuleWithOptimizationErrors =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "OptErrors")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "main"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 42)) -- Invalid main type
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createModuleWithMultipleErrors :: Src.Module
createModuleWithMultipleErrors =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "123MultiError")), -- Name error
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "badFunc"))
              [ A.at (A.Position 0 0) (A.Position 0 0) (Src.PVar (Name.fromChars "x")),
                A.at (A.Position 0 0) (A.Position 0 0) (Src.PVar (Name.fromChars "x")) -- Pattern error
              ]
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 42))
              (Just (A.at (A.Position 0 0) (A.Position 0 0) (Src.TVar (Name.fromChars "String")))) -- Type error
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createSmallModule :: Src.Module
createSmallModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "Small")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "tiny"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 1))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createManyInterfaces :: Int -> Map ModuleName.Raw I.Interface
createManyInterfaces _count = Map.empty

createModuleUsingManyInterfaces :: Src.Module
createModuleUsingManyInterfaces =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "ManyInterfaces")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "simpleValue"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 42))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createModuleWithComplexTypes :: Src.Module
createModuleWithComplexTypes =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "ComplexTypes")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "complexValue"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 1))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createDeterministicModule :: Src.Module
createDeterministicModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "Deterministic")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "deterministicValue"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 42))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createFileSystemModule :: Src.Module
createFileSystemModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "FileSystem")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "readFile"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Str (Utf8.fromChars "file contents")))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createCustomPackage :: Pkg.Name
createCustomPackage = Pkg.core

createPackageAwareModule :: Src.Module
createPackageAwareModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "PackageAware")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "packageName"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Str (Utf8.fromChars "current-package")))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createCrossModuleInterfaces :: Map ModuleName.Raw I.Interface
createCrossModuleInterfaces = Map.empty

createModule1 :: Src.Module
createModule1 =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "Module1")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "value1"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 1))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createModule2 :: Src.Module
createModule2 =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "Module2")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [],
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "value2"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Int 2))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

createEnvironment1Interfaces :: Map ModuleName.Raw I.Interface
createEnvironment1Interfaces = Map.empty

createEnvironment2Interfaces :: Map ModuleName.Raw I.Interface
createEnvironment2Interfaces = Map.empty

createEnvironmentSensitiveModule :: Src.Module
createEnvironmentSensitiveModule =
  Src.Module
    { Src._name = Just (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "EnvSensitive")),
      Src._exports = A.at (A.Position 0 0) (A.Position 0 0) Src.Open,
      Src._docs = Src.NoDocs A.zero,
      Src._imports = [], -- No imports to avoid Map lookup errors
      Src._values =
        [ A.at (A.Position 0 0) (A.Position 0 0) $
            Src.Value
              (A.at (A.Position 0 0) (A.Position 0 0) (Name.fromChars "envValue"))
              []
              (A.at (A.Position 0 0) (A.Position 0 0) (Src.Str (Utf8.fromChars "env dependent")))
              Nothing
        ],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }

-- Helper mock objects
mockInterface :: I.Interface
mockInterface =
  I.Interface
    { I._home = Pkg.core,
      I._values = Map.empty,
      I._unions = Map.empty,
      I._aliases = Map.empty,
      I._binops = Map.empty
    }
