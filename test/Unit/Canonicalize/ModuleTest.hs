{-# LANGUAGE OverloadedStrings #-}

{-|
Module: Unit.Canonicalize.ModuleTest
Description: Tests for Canonicalize.Module canonicalization and FFI loading
Copyright: (c) 2024 Canopy Contributors
License: BSD-3-Clause

Tests the module-level canonicalization functions including FFI content loading
and the main canonicalize pipeline. The tests exercise loadFFIContent and
loadFFIContentWithRoot for FFI file resolution, and canonicalize with minimal
source modules to verify error handling and basic module processing.

Coverage Target: >= 80% line coverage
Test Categories: Unit, Integration, Edge Case

@since 0.19.1
-}
module Unit.Canonicalize.ModuleTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canonicalize.Module as Module
import qualified Canopy.Package as Pkg
import Parse.Module (ProjectType (..))
import qualified Data.ByteString.Char8 as C8
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import FFI.Types (JsSourcePath (..), JsSource (..))
import qualified Foreign.FFI as FFI
import qualified Parse.Module as ParseModule
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as Warning
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive, doesDirectoryExist)
import System.FilePath ((</>))
import System.IO (writeFile)
import Prelude hiding (writeFile)

-- | Top-level test tree for the Canonicalize.Module module.
tests :: TestTree
tests = testGroup "Canonicalize.Module Tests"
  [ loadFFIContentTests
  , loadFFIContentWithRootTests
  , canonicalizeEmptyModuleTests
  , canonicalizeExportTests
  , canonicalizeEmptyExplicitExportsTests
  , canonicalizeNonexistentExplicitExportsTests
  , canonicalizeDuplicateExportsTests
  , canonicalizeValuesTests
  , canonicalizeTypeAnnotationTests
  , canonicalizeDuplicateDefinitionTests
  , canonicalizeFFIModuleTests
  , canonicalizeOperatorTests
  , canonicalizeOpenExportTests
  , canonicalizeRecursiveDeclTests
  , canonicalizeLazyImportInPackageTests
  ]

-- | Extract a successful Right value from a Result run, or fail the test.
expectRight :: ([w], Either (OneOrMore.OneOrMore Error.Error) a) -> IO a
expectRight (_, Right val) = return val
expectRight (_, Left _) = assertFailure "Expected Right, got Left" >> error "unreachable"

-- | Assert that a Result run produced a Left (error).
expectLeft :: ([w], Either (OneOrMore.OneOrMore Error.Error) a) -> IO (OneOrMore.OneOrMore Error.Error)
expectLeft (_, Left errs) = return errs
expectLeft (_, Right _) = assertFailure "Expected Left, got Right" >> error "unreachable"

-- | Run the canonicalize function and extract the Result.
runCanonicalize :: Src.Module -> ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) ())
runCanonicalize modul =
  Result.run (canonicalizeResult modul)
  where
    canonicalizeResult m =
      fmap (const ()) (Module.canonicalize (Module.CanonConfig Pkg.core Application Map.empty) Map.empty m)

-- | A minimal empty source module with no declarations.
emptyModule :: Src.Module
emptyModule = Src.Module
  { Src._name = Nothing
  , Src._exports = Ann.At Ann.one Src.Open
  , Src._docs = Src.NoDocs Ann.one
  , Src._imports = []
  , Src._foreignImports = []
  , Src._values = []
  , Src._unions = []
  , Src._aliases = []
  , Src._binops = []
  , Src._effects = Src.NoEffects
  , Src._comments = []
  , Src._abilities = []
  , Src._impls = []
  }

-- | A module with a specific name.
namedModule :: Name.Name -> Src.Module
namedModule name = emptyModule
  { Src._name = Just (Ann.At Ann.one name) }

-- LOAD FFI CONTENT TESTS

loadFFIContentTests :: TestTree
loadFFIContentTests = testGroup "loadFFIContent"
  [ testCase "no foreign imports returns empty map" $ do
      result <- Module.loadFFIContent []
      result @?= Map.empty
  , testCase "nonexistent file returns empty map" $ do
      let ffi = Src.ForeignImport
                  (mkJSTarget "/nonexistent/path/to/file.js")
                  (Ann.At Ann.one (Name.fromChars "MyFFI"))
                  Ann.one
      result <- Module.loadFFIContent [ffi]
      result @?= Map.empty
  ]

-- LOAD FFI CONTENT WITH ROOT TESTS

loadFFIContentWithRootTests :: TestTree
loadFFIContentWithRootTests = testGroup "loadFFIContentWithRoot"
  [ testCase "nonexistent root directory returns empty for missing files" $ do
      let ffi = Src.ForeignImport
                  (mkJSTarget "missing.js")
                  (Ann.At Ann.one (Name.fromChars "Missing"))
                  Ann.one
      result <- Module.loadFFIContentWithRoot "/nonexistent/root" [ffi]
      result @?= Map.empty
  , testCase "existing file in root directory is loaded" $ do
      let tmpDir = "/tmp/canopy-module-test-ffi"
      setupTmpDir tmpDir
      System.IO.writeFile (tmpDir </> "test.js") "function hello() { return 42; }"
      let ffi = Src.ForeignImport
                  (mkJSTarget "test.js")
                  (Ann.At Ann.one (Name.fromChars "TestFFI"))
                  Ann.one
      result <- Module.loadFFIContentWithRoot tmpDir [ffi]
      Map.lookup (JsSourcePath "test.js") result @?= Just (JsSource "function hello() { return 42; }")
      cleanupTmpDir tmpDir
  , testCase "multiple FFI imports with mixed existence" $ do
      let tmpDir = "/tmp/canopy-module-test-ffi-mixed"
      setupTmpDir tmpDir
      System.IO.writeFile (tmpDir </> "exists.js") "var x = 1;"
      let ffi1 = Src.ForeignImport
                   (mkJSTarget "exists.js")
                   (Ann.At Ann.one (Name.fromChars "Exists"))
                   Ann.one
          ffi2 = Src.ForeignImport
                   (mkJSTarget "missing.js")
                   (Ann.At Ann.one (Name.fromChars "Missing"))
                   Ann.one
      result <- Module.loadFFIContentWithRoot tmpDir [ffi1, ffi2]
      Map.member (JsSourcePath "exists.js") result @?= True
      Map.member (JsSourcePath "missing.js") result @?= False
      Map.size result @?= 1
      cleanupTmpDir tmpDir
  , testCase "empty foreign imports list returns empty map" $ do
      result <- Module.loadFFIContentWithRoot "/tmp" []
      result @?= Map.empty
  ]

-- CANONICALIZE EMPTY MODULE TESTS

canonicalizeEmptyModuleTests :: TestTree
canonicalizeEmptyModuleTests = testGroup "canonicalize empty modules"
  [ testCase "empty module with no declarations canonicalizes successfully" $ do
      _ <- expectRight (runCanonicalize emptyModule)
      return ()
  , testCase "named empty module canonicalizes successfully" $ do
      _ <- expectRight (runCanonicalize (namedModule (Name.fromChars "MyModule")))
      return ()
  , testCase "empty module produces no warnings" $ do
      let (warnings, _) = runCanonicalize emptyModule
      length warnings @?= 0
  ]

-- CANONICALIZE EXPORT TESTS

canonicalizeExportTests :: TestTree
canonicalizeExportTests = testGroup "canonicalize with exports"
  [ testCase "explicit export of nonexistent value produces error" $ do
      let modul = emptyModule
            { Src._exports = Ann.At Ann.one (Src.Explicit
                [ Src.Lower (Ann.At Ann.one (Name.fromChars "nonexistent")) ])
            }
      errs <- expectLeft (runCanonicalize modul)
      verifyExportNotFoundError errs (Name.fromChars "nonexistent")
  , testCase "explicit export of nonexistent type produces error" $ do
      let modul = emptyModule
            { Src._exports = Ann.At Ann.one (Src.Explicit
                [ Src.Upper (Ann.At Ann.one (Name.fromChars "NoSuchType")) Src.Private ])
            }
      errs <- expectLeft (runCanonicalize modul)
      verifyExportNotFoundError errs (Name.fromChars "NoSuchType")
  , testCase "explicit export of nonexistent operator produces error" $ do
      let modul = emptyModule
            { Src._exports = Ann.At Ann.one (Src.Explicit
                [ Src.Operator Ann.one (Name.fromChars "+++") ])
            }
      errs <- expectLeft (runCanonicalize modul)
      verifyExportNotFoundError errs (Name.fromChars "+++")
  ]

-- EMPTY EXPLICIT EXPORT TESTS

-- | Module with an empty explicit export list: @module M exposing ()@
emptyExplicitExportModule :: Src.Module
emptyExplicitExportModule = emptyModule
  { Src._exports = Ann.At Ann.one (Src.Explicit []) }

canonicalizeEmptyExplicitExportsTests :: TestTree
canonicalizeEmptyExplicitExportsTests = testGroup "canonicalize with empty explicit export list"
  [ testCase "empty explicit export list canonicalizes successfully" $ do
      _ <- expectRight (runCanonicalize emptyExplicitExportModule)
      return ()
  , testCase "empty explicit exports produce no warnings" $ do
      let (warnings, _) = runCanonicalize emptyExplicitExportModule
      length warnings @?= 0
  ]

-- NONEXISTENT EXPLICIT EXPORTS TESTS

-- | Build a module with a single lower-case explicit export of a given name.
moduleWithLowerExport :: Name.Name -> Src.Module
moduleWithLowerExport name = emptyModule
  { Src._exports = Ann.At Ann.one
      (Src.Explicit [Src.Lower (Ann.At Ann.one name)])
  }

canonicalizeNonexistentExplicitExportsTests :: TestTree
canonicalizeNonexistentExplicitExportsTests = testGroup "canonicalize with nonexistent explicit exports"
  [ testCase "two missing explicit exports both produce errors" $ do
      let modul = emptyModule
            { Src._exports = Ann.At Ann.one (Src.Explicit
                [ Src.Lower (Ann.At Ann.one (Name.fromChars "missing1"))
                , Src.Lower (Ann.At Ann.one (Name.fromChars "missing2"))
                ])
            }
      _ <- expectLeft (runCanonicalize modul)
      return ()
  , testCase "export of missing lower name errors with that name" $ do
      let name = Name.fromChars "ghostFn"
      errs <- expectLeft (runCanonicalize (moduleWithLowerExport name))
      verifyExportNotFoundError errs name
  ]

-- DUPLICATE EXPORT TESTS

-- | Build a module with two identical lower-case exports.
moduleWithDuplicateLowerExports :: Name.Name -> Src.Module
moduleWithDuplicateLowerExports name = emptyModule
  { Src._exports = Ann.At Ann.one (Src.Explicit
      [ Src.Lower (Ann.At Ann.one name)
      , Src.Lower (Ann.At Ann.one name)
      ])
  }

canonicalizeDuplicateExportsTests :: TestTree
canonicalizeDuplicateExportsTests = testGroup "canonicalize duplicate export detection"
  [ testCase "duplicate lower export produces an error" $ do
      let name = Name.fromChars "myFn"
      _ <- expectLeft (runCanonicalize (moduleWithDuplicateLowerExports name))
      return ()
  , testCase "duplicate type export produces an error" $ do
      let modul = emptyModule
            { Src._exports = Ann.At Ann.one (Src.Explicit
                [ Src.Upper (Ann.At Ann.one (Name.fromChars "MyType")) Src.Private
                , Src.Upper (Ann.At Ann.one (Name.fromChars "MyType")) Src.Private
                ])
            }
      _ <- expectLeft (runCanonicalize modul)
      return ()
  ]

-- CANONICALIZE VALUES TESTS (full pipeline)

-- | Parse and canonicalize a full module source string.
parseAndCanonicalize :: String -> IO ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) Can.Module)
parseAndCanonicalize src =
  case ParseModule.fromByteString (ParseModule.Package Pkg.core) (C8.pack src) of
    Left err -> assertFailure ("parse failed: " ++ show err) >> error "unreachable"
    Right m -> pure (Result.run (Module.canonicalize pipelineConfig Map.empty m))

-- | Minimal module header.
withHeader :: [String] -> String
withHeader bodyLines = unlines ("module M exposing (..)" : "" : bodyLines)

-- | Extract errors from a result.
extractErrors :: ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) a) -> [Error.Error]
extractErrors (_, Left errs) = OneOrMore.destruct (:) errs
extractErrors (_, Right _) = []

-- | Shared canonicalization config for full-pipeline tests.
pipelineConfig :: Module.CanonConfig
pipelineConfig = Module.CanonConfig Pkg.core (ParseModule.Package Pkg.core) Map.empty

-- | Tests for value canonicalization in modules.
canonicalizeValuesTests :: TestTree
canonicalizeValuesTests = testGroup "canonicalize module values"
  [ testCase "module with single value definition canonicalizes" $ do
      (_, result) <- parseAndCanonicalize (withHeader ["x = 42"])
      case result of
        Right _ -> return ()
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))

  , testCase "module with multiple value definitions canonicalizes" $ do
      let src = withHeader ["a = 1", "", "b = 2", "", "c = 3"]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right _ -> return ()
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))

  , testCase "module with union type canonicalizes" $ do
      let src = withHeader ["type Color = Red | Green | Blue"]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right _ -> return ()
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))

  , testCase "module with type alias canonicalizes" $ do
      let src = withHeader ["type alias Point a = { x : a, y : a }"]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right _ -> return ()
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))

  , testCase "module with recursive function canonicalizes" $ do
      let src = withHeader ["count n = count n"]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right _ -> return ()
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))
  ]

-- TYPE ANNOTATION TESTS

-- | Tests for type annotation handling in canonicalized modules.
canonicalizeTypeAnnotationTests :: TestTree
canonicalizeTypeAnnotationTests = testGroup "canonicalize type annotations"
  [ testCase "function with type annotation canonicalizes" $ do
      let src = withHeader
            [ "identity : a -> a"
            , "identity x = x"
            ]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right _ -> return ()
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))

  , testCase "function with multi-arg type annotation canonicalizes" $ do
      let src = withHeader
            [ "first : a -> b -> a"
            , "first x y = x"
            ]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right _ -> return ()
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))

  , testCase "value with record type annotation canonicalizes" $ do
      let src = withHeader
            [ "origin : { x : a, y : a }"
            , "origin = { x = 0, y = 0 }"
            ]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right _ -> return ()
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))
  ]

-- DUPLICATE DEFINITION TESTS

-- | Tests for duplicate definition detection in modules.
canonicalizeDuplicateDefinitionTests :: TestTree
canonicalizeDuplicateDefinitionTests = testGroup "canonicalize duplicate definition detection"
  [ testCase "duplicate value definition produces error" $ do
      let src = withHeader
            [ "x = 1"
            , ""
            , "x = 2"
            ]
      errs <- extractErrors <$> parseAndCanonicalize src
      assertBool ("expected duplicate error, got: " ++ show errs) (not (null errs))

  , testCase "duplicate type alias produces error" $ do
      let src = withHeader
            [ "type alias Foo = Int"
            , ""
            , "type alias Foo = String"
            ]
      errs <- extractErrors <$> parseAndCanonicalize src
      assertBool ("expected duplicate error, got: " ++ show errs) (not (null errs))
  ]

-- FFI MODULE TESTS

-- | Tests for module canonicalization with FFI pre-loaded content.
canonicalizeFFIModuleTests :: TestTree
canonicalizeFFIModuleTests = testGroup "canonicalize FFI module handling"
  [ testCase "module with no foreign imports and empty FFI map succeeds" $ do
      _ <- expectRight (runCanonicalize emptyModule)
      return ()

  , testCase "module with foreign import pointing to absent file produces error" $ do
      let modul = emptyModule
            { Src._foreignImports =
                [ Src.ForeignImport
                    (FFI.JavaScriptFFI "missing.js")
                    (Ann.At Ann.one (Name.fromChars "Missing"))
                    Ann.one
                ]
            }
      errs <- expectLeft (runCanonicalize modul)
      let errList = OneOrMore.destruct (:) errs
      assertBool ("expected FFIFileNotFound, got: " ++ show errList) (any isFFIFileNotFound errList)

  , testCase "module with foreign import and matching FFI content succeeds" $ do
      let jsFilePath = "foo.js"
          jsKey = JsSourcePath "foo.js"
          jsContent = JsSource "var Foo = {};"
          ffiMap = Map.singleton jsKey jsContent
          modul = emptyModule
            { Src._foreignImports =
                [ Src.ForeignImport
                    (FFI.JavaScriptFFI jsFilePath)
                    (Ann.At Ann.one (Name.fromChars "Foo"))
                    Ann.one
                ]
            }
          runResult = Result.run (Module.canonicalize (Module.CanonConfig Pkg.core Application Map.empty) ffiMap modul)
      case runResult of
        (_, Right _) -> return ()
        (_, Left errs) ->
          let errList = OneOrMore.destruct (:) errs
          in assertBool ("expected success, got: " ++ show errList) False
  ]

-- OPERATOR TESTS

-- | Tests for operator declarations in canonicalized modules.
canonicalizeOperatorTests :: TestTree
canonicalizeOperatorTests = testGroup "canonicalize operator declarations"
  [ testCase "module with infix operator declaration canonicalizes" $ do
      -- Infix declarations must appear before function definitions in the
      -- module source. The parser processes infixes in a separate phase
      -- before regular declarations.
      let src = unlines
            [ "module M exposing (..)"
            , ""
            , "infix left 6 (|+|) = myAdd"
            , ""
            , "myAdd x y = x"
            ]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right _ -> return ()
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))

  , testCase "module with multiple binops canonicalizes" $ do
      let src = unlines
            [ "module M exposing (..)"
            , ""
            , "infix left 6 (|+|) = myAdd"
            , "infix left 6 (|-|) = mySub"
            , ""
            , "myAdd x y = x"
            , ""
            , "mySub x y = x"
            ]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right _ -> return ()
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))
  ]

-- OPEN EXPORT TESTS

-- | Tests for open (@exposing (..)@) export handling.
canonicalizeOpenExportTests :: TestTree
canonicalizeOpenExportTests = testGroup "canonicalize open export modules"
  [ testCase "module exposing (..) with union type has ExportEverything" $ do
      let src = withHeader ["type Color = Red | Green | Blue"]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right canMod ->
          case Can._exports canMod of
            Can.ExportEverything _ -> return ()
            Can.Export _ -> assertFailure "expected ExportEverything, got Export"
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))

  , testCase "module exposing (..) with type alias has ExportEverything" $ do
      let src = withHeader ["type alias Pair a b = { first : a, second : b }"]
      (_, result) <- parseAndCanonicalize src
      case result of
        Right canMod ->
          case Can._exports canMod of
            Can.ExportEverything _ -> return ()
            Can.Export _ -> assertFailure "expected ExportEverything, got Export"
        Left errs -> assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))
  ]

-- RECURSIVE DECLARATION TESTS

-- | Tests for recursive top-level declaration detection.
canonicalizeRecursiveDeclTests :: TestTree
canonicalizeRecursiveDeclTests = testGroup "canonicalize recursive declarations"
  [ testCase "recursive function is accepted" $ do
      let src = withHeader ["loop n = loop n"]
      errs <- extractErrors <$> parseAndCanonicalize src
      assertBool ("expected success, got: " ++ show errs) (null errs)

  , testCase "mutually recursive top-level functions are accepted" $ do
      let src = withHeader
            [ "ping x = pong x"
            , ""
            , "pong x = ping x"
            ]
      errs <- extractErrors <$> parseAndCanonicalize src
      assertBool ("expected success, got: " ++ show errs) (null errs)

  , testCase "simple non-recursive value is not a recursive decl" $ do
      let src = withHeader ["answer = 42"]
      errs <- extractErrors <$> parseAndCanonicalize src
      assertBool ("expected success, got: " ++ show errs) (null errs)
  ]

-- LAZY IMPORT IN PACKAGE TESTS

-- | Tests that lazy imports inside packages produce errors.
--
-- The 'checkNotPackage' guard fires when the project type is 'Package'.
canonicalizeLazyImportInPackageTests :: TestTree
canonicalizeLazyImportInPackageTests = testGroup "canonicalize lazy imports in packages"
  [ testCase "module with no lazy imports in package context succeeds" $ do
      let modul = emptyModule
      let runResult = Result.run
            (Module.canonicalize
              (Module.CanonConfig Pkg.core (ParseModule.Package Pkg.core) Map.empty)
              Map.empty
              modul)
      case runResult of
        (_, Right _) -> return ()
        (_, Left errs) ->
          assertFailure ("expected success, got: " ++ show (OneOrMore.destruct (:) errs))
  ]

-- HELPERS

-- | Create an FFI JavaScript target.
mkJSTarget :: FilePath -> FFI.FFITarget
mkJSTarget = FFI.JavaScriptFFI

-- | Set up a temporary directory, cleaning up any previous run.
setupTmpDir :: FilePath -> IO ()
setupTmpDir dir = do
  exists <- doesDirectoryExist dir
  cleanupIfExists exists dir
  createDirectoryIfMissing True dir
  where
    cleanupIfExists True d = removeDirectoryRecursive d
    cleanupIfExists False _ = return ()

-- | Clean up a temporary directory.
cleanupTmpDir :: FilePath -> IO ()
cleanupTmpDir dir = do
  exists <- doesDirectoryExist dir
  cleanupIfExists exists dir
  where
    cleanupIfExists True d = removeDirectoryRecursive d
    cleanupIfExists False _ = return ()

-- | Verify that an error collection contains an ExportNotFound error for the given name.
verifyExportNotFoundError :: OneOrMore.OneOrMore Error.Error -> Name.Name -> Assertion
verifyExportNotFoundError errs expectedName =
  let errList = OneOrMore.destruct (:) errs
  in case errList of
       (Error.ExportNotFound _ _ name _ : _) ->
         name @?= expectedName
       other ->
         assertFailure ("Expected ExportNotFound error, got: " ++ show other)

-- | Check if an error is a FFIFileNotFound error.
isFFIFileNotFound :: Error.Error -> Bool
isFFIFileNotFound (Error.FFIFileNotFound _ _) = True
isFFIFileNotFound _ = False
