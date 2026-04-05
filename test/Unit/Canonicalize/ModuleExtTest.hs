{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Canonicalize.ModuleExtTest - Extended tests for Canonicalize.Module
--
-- Tests module canonicalization with value declarations, operator declarations,
-- type unions/aliases, derived function name collection, and the canonicalizeWithIO
-- legacy path.
--
-- @since 0.19.1
module Unit.Canonicalize.ModuleExtTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified AST.Source as Src
import qualified Canonicalize.Module as Module
import qualified Canopy.Package as Pkg
import Parse.Module (ProjectType (..))
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as Warning

-- | Top-level test tree.
tests :: TestTree
tests = testGroup "Canonicalize.Module Extended Tests"
  [ moduleWithValuesTests
  , canonicalizeWithIOTests
  , openExportTests
  , duplicateExportTests
  ]

-- | Run canonicalize and return the result.
runCanonicalize :: Src.Module -> ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) ())
runCanonicalize modul =
  Result.run (fmap (const ()) (Module.canonicalize (Module.CanonConfig Pkg.core Application Map.empty) Map.empty modul))

-- | Extract Right value or fail the test.
expectRight :: ([w], Either (OneOrMore.OneOrMore Error.Error) a) -> IO a
expectRight (_, Right val) = return val
expectRight (_, Left _) = assertFailure "Expected Right, got Left" >> error "unreachable"

-- | Extract Left errors or fail the test.
expectLeft :: ([w], Either (OneOrMore.OneOrMore Error.Error) a) -> IO (OneOrMore.OneOrMore Error.Error)
expectLeft (_, Left errs) = return errs
expectLeft (_, Right _) = assertFailure "Expected Left, got Right" >> error "unreachable"

-- | Minimal empty module template.
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

-- MODULE WITH VALUES TESTS

moduleWithValuesTests :: TestTree
moduleWithValuesTests = testGroup "module with value declarations"
  [ testCase "module with one simple value canonicalizes successfully" $ do
      let valueName = Ann.At Ann.one (Name.fromChars "myVal")
          body = Ann.At Ann.one (Src.Int 42)
          value = Ann.At Ann.one (Src.Value valueName [] body Nothing Nothing)
          modul = emptyModule { Src._values = [value] }
      _ <- expectRight (runCanonicalize modul)
      return ()

  , testCase "module with multiple values canonicalizes successfully" $ do
      let mkValue nameStr bodyInt =
            Ann.At Ann.one (Src.Value
              (Ann.At Ann.one (Name.fromChars nameStr))
              []
              (Ann.At Ann.one (Src.Int bodyInt))
              Nothing
              Nothing)
          modul = emptyModule
            { Src._values = [mkValue "x" 1, mkValue "y" 2, mkValue "z" 3] }
      _ <- expectRight (runCanonicalize modul)
      return ()

  , testCase "module with duplicate value names produces error" $ do
      let mkValue nameStr =
            Ann.At Ann.one (Src.Value
              (Ann.At Ann.one (Name.fromChars nameStr))
              []
              (Ann.At Ann.one (Src.Int 0))
              Nothing
              Nothing)
          modul = emptyModule
            { Src._values = [mkValue "duplicate", mkValue "duplicate"] }
      _ <- expectLeft (runCanonicalize modul)
      return ()

  , testCase "module with function value (one arg) canonicalizes successfully" $ do
      let argPat = Ann.At Ann.one (Src.PVar (Name.fromChars "n"))
          body = Ann.At Ann.one (Src.Var Src.LowVar (Name.fromChars "n"))
          value = Ann.At Ann.one (Src.Value
            (Ann.At Ann.one (Name.fromChars "identity"))
            [argPat]
            body
            Nothing
            Nothing)
          modul = emptyModule { Src._values = [value] }
      _ <- expectRight (runCanonicalize modul)
      return ()
  ]

-- CANONICALIZE WITH IO TESTS

canonicalizeWithIOTests :: TestTree
canonicalizeWithIOTests = testGroup "canonicalizeWithIO legacy path"
  [ testCase "canonicalizeWithIO on empty module succeeds" $ do
      result <- Module.canonicalizeWithIO Pkg.core Map.empty emptyModule
      let (_, outcome) = Result.run (fmap (const ()) result)
      case outcome of
        Right _ -> return ()
        Left err -> assertFailure ("canonicalizeWithIO failed: " ++ show (OneOrMore.destruct (:) err))

  , testCase "canonicalizeWithIO on named module succeeds" $ do
      let modul = emptyModule { Src._name = Just (Ann.At Ann.one (Name.fromChars "MyMod")) }
      result <- Module.canonicalizeWithIO Pkg.core Map.empty modul
      let (_, outcome) = Result.run (fmap (const ()) result)
      case outcome of
        Right _ -> return ()
        Left err -> assertFailure ("canonicalizeWithIO failed: " ++ show (OneOrMore.destruct (:) err))
  ]

-- OPEN EXPORT TESTS

openExportTests :: TestTree
openExportTests = testGroup "open export (exposing ..)"
  [ testCase "open export module canonicalizes successfully" $ do
      let modul = emptyModule { Src._exports = Ann.At Ann.one Src.Open }
      _ <- expectRight (runCanonicalize modul)
      return ()

  , testCase "open export module with values canonicalizes successfully" $ do
      let value = Ann.At Ann.one (Src.Value
            (Ann.At Ann.one (Name.fromChars "helper"))
            []
            (Ann.At Ann.one (Src.Int 0))
            Nothing
            Nothing)
          modul = emptyModule
            { Src._exports = Ann.At Ann.one Src.Open
            , Src._values = [value]
            }
      _ <- expectRight (runCanonicalize modul)
      return ()
  ]

-- DUPLICATE EXPORT TESTS

duplicateExportTests :: TestTree
duplicateExportTests = testGroup "explicit export errors"
  [ testCase "exporting same value twice produces error" $ do
      let valName = Name.fromChars "myFn"
          value = Ann.At Ann.one (Src.Value
            (Ann.At Ann.one valName)
            []
            (Ann.At Ann.one (Src.Int 1))
            Nothing
            Nothing)
          exports = Src.Explicit
            [ Src.Lower (Ann.At Ann.one valName)
            , Src.Lower (Ann.At Ann.one valName)
            ]
          modul = emptyModule
            { Src._exports = Ann.At Ann.one exports
            , Src._values = [value]
            }
      _ <- expectLeft (runCanonicalize modul)
      return ()

  , testCase "exporting existing value succeeds" $ do
      let valName = Name.fromChars "exported"
          value = Ann.At Ann.one (Src.Value
            (Ann.At Ann.one valName)
            []
            (Ann.At Ann.one (Src.Int 5))
            Nothing
            Nothing)
          exports = Src.Explicit [Src.Lower (Ann.At Ann.one valName)]
          modul = emptyModule
            { Src._exports = Ann.At Ann.one exports
            , Src._values = [value]
            }
      _ <- expectRight (runCanonicalize modul)
      return ()
  ]
