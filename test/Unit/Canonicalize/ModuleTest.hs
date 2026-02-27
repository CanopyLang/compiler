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

import qualified AST.Source as Src
import qualified Canonicalize.Module as Module
import qualified Canopy.Package as Pkg
import Parse.Module (ProjectType (..))
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.OneOrMore as OneOrMore
import qualified Foreign.FFI as FFI
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as W
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
runCanonicalize :: Src.Module -> ([W.Warning], Either (OneOrMore.OneOrMore Error.Error) ())
runCanonicalize modul =
  Result.run (canonicalizeResult modul)
  where
    canonicalizeResult m =
      fmap (const ()) (Module.canonicalize Pkg.core Application Map.empty Map.empty m)

-- | A minimal empty source module with no declarations.
emptyModule :: Src.Module
emptyModule = Src.Module
  { Src._name = Nothing
  , Src._exports = A.At A.one Src.Open
  , Src._docs = Src.NoDocs A.one
  , Src._imports = []
  , Src._foreignImports = []
  , Src._values = []
  , Src._unions = []
  , Src._aliases = []
  , Src._binops = []
  , Src._effects = Src.NoEffects
  }

-- | A module with a specific name.
namedModule :: Name.Name -> Src.Module
namedModule name = emptyModule
  { Src._name = Just (A.At A.one name) }

-- LOAD FFI CONTENT TESTS

loadFFIContentTests :: TestTree
loadFFIContentTests = testGroup "loadFFIContent"
  [ testCase "no foreign imports returns empty map" $ do
      result <- Module.loadFFIContent []
      result @?= Map.empty
  , testCase "nonexistent file returns empty map" $ do
      let ffi = Src.ForeignImport
                  (mkJSTarget "/nonexistent/path/to/file.js")
                  (A.At A.one (Name.fromChars "MyFFI"))
                  A.one
      result <- Module.loadFFIContent [ffi]
      result @?= Map.empty
  ]

-- LOAD FFI CONTENT WITH ROOT TESTS

loadFFIContentWithRootTests :: TestTree
loadFFIContentWithRootTests = testGroup "loadFFIContentWithRoot"
  [ testCase "nonexistent root directory returns empty for missing files" $ do
      let ffi = Src.ForeignImport
                  (mkJSTarget "missing.js")
                  (A.At A.one (Name.fromChars "Missing"))
                  A.one
      result <- Module.loadFFIContentWithRoot "/nonexistent/root" [ffi]
      result @?= Map.empty
  , testCase "existing file in root directory is loaded" $ do
      let tmpDir = "/tmp/canopy-module-test-ffi"
      setupTmpDir tmpDir
      System.IO.writeFile (tmpDir </> "test.js") "function hello() { return 42; }"
      let ffi = Src.ForeignImport
                  (mkJSTarget "test.js")
                  (A.At A.one (Name.fromChars "TestFFI"))
                  A.one
      result <- Module.loadFFIContentWithRoot tmpDir [ffi]
      Map.lookup "test.js" result @?= Just "function hello() { return 42; }"
      cleanupTmpDir tmpDir
  , testCase "multiple FFI imports with mixed existence" $ do
      let tmpDir = "/tmp/canopy-module-test-ffi-mixed"
      setupTmpDir tmpDir
      System.IO.writeFile (tmpDir </> "exists.js") "var x = 1;"
      let ffi1 = Src.ForeignImport
                   (mkJSTarget "exists.js")
                   (A.At A.one (Name.fromChars "Exists"))
                   A.one
          ffi2 = Src.ForeignImport
                   (mkJSTarget "missing.js")
                   (A.At A.one (Name.fromChars "Missing"))
                   A.one
      result <- Module.loadFFIContentWithRoot tmpDir [ffi1, ffi2]
      Map.member "exists.js" result @?= True
      Map.member "missing.js" result @?= False
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
            { Src._exports = A.At A.one (Src.Explicit
                [ Src.Lower (A.At A.one (Name.fromChars "nonexistent")) ])
            }
      errs <- expectLeft (runCanonicalize modul)
      verifyExportNotFoundError errs (Name.fromChars "nonexistent")
  , testCase "explicit export of nonexistent type produces error" $ do
      let modul = emptyModule
            { Src._exports = A.At A.one (Src.Explicit
                [ Src.Upper (A.At A.one (Name.fromChars "NoSuchType")) Src.Private ])
            }
      errs <- expectLeft (runCanonicalize modul)
      verifyExportNotFoundError errs (Name.fromChars "NoSuchType")
  , testCase "explicit export of nonexistent operator produces error" $ do
      let modul = emptyModule
            { Src._exports = A.At A.one (Src.Explicit
                [ Src.Operator A.one (Name.fromChars "+++") ])
            }
      errs <- expectLeft (runCanonicalize modul)
      verifyExportNotFoundError errs (Name.fromChars "+++")
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
