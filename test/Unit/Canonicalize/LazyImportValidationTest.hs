{-# LANGUAGE OverloadedStrings #-}

-- | Tests for compile-time validation of lazy imports.
--
-- Validates that 'Canonicalize.Module.validateAndCollectLazyImports'
-- correctly rejects invalid lazy imports with appropriate error
-- constructors and accepts valid ones.
--
-- @since 0.19.2
module Unit.Canonicalize.LazyImportValidationTest
  ( tests,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canonicalize.Module as Module
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.Map (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Data.Set as Set
import Parse.Module (ProjectType (..))
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as Warning
import Test.Tasty
import Test.Tasty.HUnit

-- | Top-level test tree for lazy import validation.
tests :: TestTree
tests =
  testGroup
    "Lazy Import Validation"
    [ lazyImportNotFoundTests,
      lazyImportCoreModuleTests,
      lazyImportInPackageTests,
      lazyImportSelfTests,
      lazyImportKernelTests,
      validLazyImportTests,
      nonLazyImportTests
    ]

-- NON-EXISTENT MODULE TESTS

lazyImportNotFoundTests :: TestTree
lazyImportNotFoundTests =
  testGroup
    "LazyImportNotFound"
    [ testCase "lazy import of non-existent module produces NotFound error" $ do
        let modul = moduleWithLazyImport "Dashboard"
        errs <- expectErrors (runCanonicalize Application Map.empty modul)
        assertErrorIs isLazyImportNotFound errs,
      testCase "NotFound error includes the import name" $ do
        let modul = moduleWithLazyImport "Dashboard"
        errs <- expectErrors (runCanonicalize Application Map.empty modul)
        assertLazyNotFoundName (Name.fromChars "Dashboard") errs,
      testCase "NotFound error includes available module names as suggestions" $ do
        let ifaces = Map.fromList [(Name.fromChars "DashboardView", emptyInterface)]
            modul = moduleWithLazyImport "Dashboard"
        errs <- expectErrors (runCanonicalize Application ifaces modul)
        assertLazyNotFoundSuggestions [Name.fromChars "DashboardView"] errs
    ]

-- CORE MODULE TESTS

lazyImportCoreModuleTests :: TestTree
lazyImportCoreModuleTests =
  testGroup
    "LazyImportCoreModule"
    [ testCase "lazy import of List produces CoreModule error" $ do
        let ifaces = Map.fromList [(Name.fromChars "List", emptyInterface)]
            modul = moduleWithLazyImport "List"
        errs <- expectErrors (runCanonicalize Application ifaces modul)
        assertErrorIs isLazyImportCoreModule errs,
      testCase "lazy import of Maybe produces CoreModule error" $ do
        let ifaces = Map.fromList [(Name.fromChars "Maybe", emptyInterface)]
            modul = moduleWithLazyImport "Maybe"
        errs <- expectErrors (runCanonicalize Application ifaces modul)
        assertErrorIs isLazyImportCoreModule errs,
      testCase "lazy import of Basics produces CoreModule error" $ do
        let ifaces = Map.fromList [(Name.fromChars "Basics", emptyInterface)]
            modul = moduleWithLazyImport "Basics"
        errs <- expectErrors (runCanonicalize Application ifaces modul)
        assertErrorIs isLazyImportCoreModule errs,
      testCase "lazy import of String produces CoreModule error" $ do
        let ifaces = Map.fromList [(Name.fromChars "String", emptyInterface)]
            modul = moduleWithLazyImport "String"
        errs <- expectErrors (runCanonicalize Application ifaces modul)
        assertErrorIs isLazyImportCoreModule errs
    ]

-- PACKAGE CONTEXT TESTS

lazyImportInPackageTests :: TestTree
lazyImportInPackageTests =
  testGroup
    "LazyImportInPackage"
    [ testCase "lazy import inside a package produces InPackage error" $ do
        let ifaces = Map.fromList [(Name.fromChars "SomeModule", emptyInterface)]
            modul = moduleWithLazyImport "SomeModule"
        errs <- expectErrors (runCanonicalize (Package Pkg.core) ifaces modul)
        assertErrorIs isLazyImportInPackage errs,
      testCase "non-lazy import inside a package is fine" $ do
        let ifaces = Map.fromList [(Name.fromChars "SomeModule", emptyInterface)]
            modul = moduleWithNonLazyImport "SomeModule"
        _ <- expectSuccess (runCanonicalize (Package Pkg.core) ifaces modul)
        return ()
    ]

-- SELF-IMPORT TESTS

lazyImportSelfTests :: TestTree
lazyImportSelfTests =
  testGroup
    "LazyImportSelf"
    [ testCase "lazy import of self module produces Self error" $ do
        let ifaces = Map.fromList [(Name.fromChars "Main", emptyInterface)]
            modul = moduleWithLazyImportNamed "Main" "Main"
        errs <- expectErrors (runCanonicalize Application ifaces modul)
        assertErrorIs isLazyImportSelf errs
    ]

-- KERNEL MODULE TESTS

lazyImportKernelTests :: TestTree
lazyImportKernelTests =
  testGroup
    "LazyImportKernel"
    [ testCase "lazy import of kernel module produces Kernel error" $ do
        let kernelName = Name.fromChars "Elm.Kernel.Scheduler"
            ifaces = Map.fromList [(kernelName, emptyInterface)]
            modul = moduleWithLazyImportRaw kernelName
        errs <- expectErrors (runCanonicalize Application ifaces modul)
        assertErrorIs isLazyImportKernel errs
    ]

-- VALID LAZY IMPORT TESTS

validLazyImportTests :: TestTree
validLazyImportTests =
  testGroup
    "Valid lazy imports"
    [ testCase "lazy import of existing non-core module in application succeeds" $ do
        let ifaces = Map.fromList [(Name.fromChars "Dashboard", emptyInterface)]
            modul = moduleWithLazyImport "Dashboard"
        result <- expectSuccess (runCanonicalize Application ifaces modul)
        let lazySet = Can._lazyImports result
        Set.member (ModuleName.Canonical Pkg.core (Name.fromChars "Dashboard")) lazySet @?= True,
      testCase "multiple valid lazy imports all collected" $ do
        let ifaces =
              Map.fromList
                [ (Name.fromChars "PageA", emptyInterface),
                  (Name.fromChars "PageB", emptyInterface)
                ]
            modul = moduleWithMultipleLazyImports ["PageA", "PageB"]
        result <- expectSuccess (runCanonicalize Application ifaces modul)
        let lazySet = Can._lazyImports result
        Set.size lazySet @?= 2
    ]

-- NON-LAZY IMPORT TESTS

nonLazyImportTests :: TestTree
nonLazyImportTests =
  testGroup
    "Non-lazy imports unaffected"
    [ testCase "non-lazy imports are not validated by lazy checks" $ do
        let ifaces = Map.fromList [(Name.fromChars "SomeModule", emptyInterface)]
            modul = moduleWithNonLazyImport "SomeModule"
        _ <- expectSuccess (runCanonicalize Application ifaces modul)
        return (),
      testCase "non-lazy import produces empty lazy set" $ do
        let ifaces = Map.fromList [(Name.fromChars "SomeModule", emptyInterface)]
            modul = moduleWithNonLazyImport "SomeModule"
        result <- expectSuccess (runCanonicalize Application ifaces modul)
        let lazySet = Can._lazyImports result
        Set.null lazySet @?= True
    ]

-- HELPERS: MODULE BUILDERS

-- | Build a module with a single lazy import, module name defaults to "Main".
moduleWithLazyImport :: String -> Src.Module
moduleWithLazyImport importName =
  moduleWithLazyImportNamed "Main" importName

-- | Build a module with a given name and a single lazy import.
moduleWithLazyImportNamed :: String -> String -> Src.Module
moduleWithLazyImportNamed moduleName importName =
  emptyModule
    { Src._name = Just (Ann.At Ann.one (Name.fromChars moduleName)),
      Src._imports = [mkLazyImport (Name.fromChars importName)]
    }

-- | Build a module with a lazy import using a raw Name.
moduleWithLazyImportRaw :: Name.Name -> Src.Module
moduleWithLazyImportRaw importName =
  emptyModule
    { Src._name = Just (Ann.At Ann.one (Name.fromChars "Main")),
      Src._imports = [mkLazyImport importName]
    }

-- | Build a module with multiple lazy imports.
moduleWithMultipleLazyImports :: [String] -> Src.Module
moduleWithMultipleLazyImports importNames =
  emptyModule
    { Src._name = Just (Ann.At Ann.one (Name.fromChars "Main")),
      Src._imports = fmap (mkLazyImport . Name.fromChars) importNames
    }

-- | Build a module with a single non-lazy import.
moduleWithNonLazyImport :: String -> Src.Module
moduleWithNonLazyImport importName =
  emptyModule
    { Src._name = Just (Ann.At Ann.one (Name.fromChars "Main")),
      Src._imports = [mkNonLazyImport (Name.fromChars importName)]
    }

-- | A minimal empty source module.
emptyModule :: Src.Module
emptyModule =
  Src.Module
    { Src._name = Nothing,
      Src._exports = Ann.At Ann.one Src.Open,
      Src._docs = Src.NoDocs Ann.one,
      Src._imports = [],
      Src._foreignImports = [],
      Src._values = [],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects,
      Src._comments = [],
      Src._abilities = [],
      Src._impls = []
    }

-- | Create a lazy import.
mkLazyImport :: Name.Name -> Src.Import
mkLazyImport name =
  Src.Import (Ann.At Ann.one name) Nothing (Src.Explicit []) True

-- | Create a non-lazy import.
mkNonLazyImport :: Name.Name -> Src.Import
mkNonLazyImport name =
  Src.Import (Ann.At Ann.one name) Nothing (Src.Explicit []) False

-- | A minimal empty interface for testing module existence.
emptyInterface :: Interface.Interface
emptyInterface =
  Interface.Interface Pkg.core Map.empty Map.empty Map.empty Map.empty Map.empty

-- HELPERS: RUNNING CANONICALIZATION

-- | Run canonicalize with the given project type, interfaces, and module.
runCanonicalize ::
  ProjectType ->
  Map Name.Name Interface.Interface ->
  Src.Module ->
  ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) Can.Module)
runCanonicalize projectType ifaces modul =
  Result.run (Module.canonicalize Pkg.core projectType ifaces Map.empty modul)

-- | Extract errors from a Result run, failing if it succeeded.
expectErrors ::
  ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) Can.Module) ->
  IO [Error.Error]
expectErrors (_, Left errs) = return (OneOrMore.destruct (:) errs)
expectErrors (_, Right _) = assertFailure "Expected errors, got success" >> error "unreachable"

-- | Extract success from a Result run, failing if it errored.
expectSuccess ::
  ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) Can.Module) ->
  IO Can.Module
expectSuccess (_, Right val) = return val
expectSuccess (_, Left errs) =
  assertFailure ("Expected success, got errors: " ++ show (OneOrMore.destruct (:) errs))
    >> error "unreachable"

-- HELPERS: ERROR ASSERTIONS

-- | Assert that the first error matches the given predicate.
assertErrorIs :: (Error.Error -> Bool) -> [Error.Error] -> Assertion
assertErrorIs predicate errs =
  case filter predicate errs of
    [] -> assertFailure ("No matching error found in: " ++ show errs)
    _ -> return ()

-- | Check if an error is LazyImportNotFound.
isLazyImportNotFound :: Error.Error -> Bool
isLazyImportNotFound (Error.LazyImportNotFound _ _ _) = True
isLazyImportNotFound _ = False

-- | Check if an error is LazyImportCoreModule.
isLazyImportCoreModule :: Error.Error -> Bool
isLazyImportCoreModule (Error.LazyImportCoreModule _ _) = True
isLazyImportCoreModule _ = False

-- | Check if an error is LazyImportInPackage.
isLazyImportInPackage :: Error.Error -> Bool
isLazyImportInPackage (Error.LazyImportInPackage _ _) = True
isLazyImportInPackage _ = False

-- | Check if an error is LazyImportSelf.
isLazyImportSelf :: Error.Error -> Bool
isLazyImportSelf (Error.LazyImportSelf _ _) = True
isLazyImportSelf _ = False

-- | Check if an error is LazyImportKernel.
isLazyImportKernel :: Error.Error -> Bool
isLazyImportKernel (Error.LazyImportKernel _ _) = True
isLazyImportKernel _ = False

-- | Assert LazyImportNotFound has the expected name.
assertLazyNotFoundName :: Name.Name -> [Error.Error] -> Assertion
assertLazyNotFoundName expectedName errs =
  case filter isLazyImportNotFound errs of
    (Error.LazyImportNotFound _ name _ : _) -> name @?= expectedName
    _ -> assertFailure ("Expected LazyImportNotFound with name " ++ show expectedName)

-- | Assert LazyImportNotFound includes the expected suggestions.
assertLazyNotFoundSuggestions :: [Name.Name] -> [Error.Error] -> Assertion
assertLazyNotFoundSuggestions expectedSuggestions errs =
  case filter isLazyImportNotFound errs of
    (Error.LazyImportNotFound _ _ suggestions : _) ->
      assertBool
        ("Expected suggestions to contain " ++ show expectedSuggestions ++ " but got " ++ show suggestions)
        (all (`elem` suggestions) expectedSuggestions)
    _ -> assertFailure "Expected LazyImportNotFound with suggestions"
